local require       = require
local core          = require("apisix.core")
local pkg_loaded    = package.loaded
local sort_tab      = table.sort
local pcall         = pcall
local ipairs        = ipairs
local pairs         = pairs
local type          = type
local local_plugins = core.table.new(32, 0)
local ngx           = ngx
local tostring      = tostring
local local_plugins_hash    = core.table.new(0, 32)
local stream_local_plugins  = core.table.new(32, 0)
local stream_local_plugins_hash = core.table.new(0, 32)


local merged_route = core.lrucache.new({
    ttl = 300, count = 512
})
local local_conf


local _M = {
    version         = 0.3,

    load_times      = 0,
    plugins         = local_plugins,
    plugins_hash    = local_plugins_hash,

    stream_load_times= 0,
    stream_plugins  = stream_local_plugins,
    stream_plugins_hash = stream_local_plugins_hash,
}


local function sort_plugin(l, r)
    return l.priority > r.priority
end


local function load_plugin(name, plugins_list, is_stream_plugin)
    local pkg_name = "apisix.plugins." .. name
    if is_stream_plugin then
        pkg_name = "apisix.stream.plugins." .. name
    end
    pkg_loaded[pkg_name] = nil

    local ok, plugin = pcall(require, pkg_name)
    if not ok then
        core.log.error("failed to load plugin [", name, "] err: ", plugin)
        return
    end

    if not plugin.priority then
        core.log.error("invalid plugin [", name,
                        "], missing field: priority")
        return
    end

    if not plugin.version then
        core.log.error("invalid plugin [", name, "] missing field: version")
        return
    end

    plugin.name = name
    core.table.insert(plugins_list, plugin)

    if plugin.init then
        plugin.init()
    end

    return
end


local function load()
    core.table.clear(local_plugins)
    core.table.clear(local_plugins_hash)

    local_conf = core.config.local_conf(true)
    local plugin_names = local_conf.plugins
    if not plugin_names then
        return nil, "failed to read plugin list form local file"
    end

    if local_conf.apisix and local_conf.apisix.enable_heartbeat then
        core.table.insert(plugin_names, "heartbeat")
    end

    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
            load_plugin(name, local_plugins)
        end
    end

    -- sort by plugin's priority
    if #local_plugins > 1 then
        sort_tab(local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(local_plugins) do
        local_plugins_hash[plugin.name] = plugin
        if local_conf and local_conf.apisix
           and local_conf.apisix.enable_debug then
            core.log.warn("loaded plugin and sort by priority:",
                          " ", plugin.priority,
                          " name: ", plugin.name)
        end
    end

    _M.load_times = _M.load_times + 1
    core.log.info("load plugin times: ", _M.load_times)
    return true
end


local function load_stream()
    core.table.clear(stream_local_plugins)
    core.table.clear(stream_local_plugins_hash)

    local plugin_names = local_conf.stream_plugins
    if not plugin_names then
        core.log.warn("failed to read stream plugin list form local file")
        return true
    end

    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
            load_plugin(name, stream_local_plugins, true)
        end
    end

    -- sort by plugin's priority
    if #stream_local_plugins > 1 then
        sort_tab(stream_local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(stream_local_plugins) do
        stream_local_plugins_hash[plugin.name] = plugin
        if local_conf and local_conf.apisix
           and local_conf.apisix.enable_debug then
            core.log.warn("loaded stream plugin and sort by priority:",
                          " ", plugin.priority,
                          " name: ", plugin.name)
        end
    end

    _M.stream_load_times = _M.stream_load_times + 1
    core.log.info("stream plugins: ",
                  core.json.delay_encode(stream_local_plugins, true))
    core.log.info("load stream plugin times: ", _M.stream_load_times)
    return true
end


function _M.load()
    local_conf = core.config.local_conf(true)

    if ngx.config.subsystem == "http" then
        local ok, err = load()
        if not ok then
            core.log.error("failed to load plugins: ", err)
        end
    end

    local ok, err = load_stream()
    if not ok then
        core.log.error("failed to load stream plugins: ", err)
    end

    -- for test
    return local_plugins
end


local fetch_api_routes
do
    local routes = {}
function fetch_api_routes()
    core.table.clear(routes)

    for _, plugin in ipairs(_M.plugins) do
        local api_fun = plugin.api
        if api_fun then
            local api_routes = api_fun()
            core.log.debug("fetched api routes: ",
                           core.json.delay_encode(api_routes, true))
            for _, route in ipairs(api_routes) do
                core.table.insert(routes, {
                        method = route.methods,
                        uri = route.uri,
                        handler = function (...)
                            local code, body = route.handler(...)
                            if code or body then
                                core.response.exit(code, body)
                            end
                        end
                    })
            end
        end
    end

    return routes
end

end -- do


function _M.api_routes()
    return core.lrucache.global("plugin_routes", _M.load_times,
                                fetch_api_routes)
end


function _M.filter(user_route, plugins)
    plugins = plugins or core.table.new(#local_plugins * 2, 0)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        if local_conf and local_conf.apisix.enable_debug then
            core.response.set_header("Apisix-Plugins", "no plugin")
        end
        return plugins
    end

    for _, plugin_obj in ipairs(local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) == "table" and not plugin_conf.disable then
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end
    end

    if local_conf.apisix.enable_debug then
        local t = {}
        for i = 1, #plugins, 2 do
            core.table.insert(t, plugins[i].name)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(t, ", "))
    end

    return plugins
end


function _M.stream_filter(user_route, plugins)
    plugins = plugins or core.table.new(#stream_local_plugins * 2, 0)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        if local_conf and local_conf.apisix.enable_debug then
            core.response.set_header("Apisix-Plugins", "no plugin")
        end
        return plugins
    end

    for _, plugin_obj in ipairs(stream_local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) == "table" and not plugin_conf.disable then
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end
    end

    if local_conf.apisix.enable_debug then
        local t = {}
        for i = 1, #plugins, 2 do
            core.table.insert(t, plugins[i].name)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(t, ", "))
    end

    return plugins
end


local function merge_service_route(service_conf, route_conf)
    local new_service_conf

    if route_conf.value.plugins then
        for name, conf in pairs(route_conf.value.plugins) do
            if not new_service_conf then
                new_service_conf = core.table.deepcopy(service_conf)
            end
            new_service_conf.value.plugins[name] = conf
        end
    end

    local route_upstream = route_conf.value.upstream
    if route_upstream then
        if not new_service_conf then
            new_service_conf = core.table.deepcopy(service_conf)
        end
        new_service_conf.value.upstream = route_upstream

        if route_upstream.checks then
            route_upstream.parent = route_conf
        end

        new_service_conf.value.upstream_id = nil
        return new_service_conf
    end

    if route_conf.value.upstream_id then
        if not new_service_conf then
            new_service_conf = core.table.deepcopy(service_conf)
        end
        new_service_conf.value.upstream_id = route_conf.value.upstream_id
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(new_service_conf))
    return new_service_conf or service_conf
end


function _M.merge_service_route(service_conf, route_conf)
    core.log.info("service conf: ", core.json.delay_encode(service_conf))
    core.log.info("route conf: ", core.json.delay_encode(route_conf))

    local flag = tostring(service_conf) .. tostring(route_conf)
    local new_service_conf = merged_route(flag, nil, merge_service_route,
                                        service_conf, route_conf)

    return new_service_conf, new_service_conf ~= service_conf
end


local function merge_consumer_route(route_conf, consumer_conf)
    local new_route_conf

    if consumer_conf.plugins then
        for name, conf in pairs(consumer_conf.plugins) do
            if not new_route_conf then
                new_route_conf = core.table.deepcopy(route_conf)
            end
            new_route_conf.value.plugins[name] = conf
        end
    end

    core.log.info("merged conf : ", core.json.delay_encode(new_route_conf))
    return new_route_conf or route_conf
end


function _M.merge_consumer_route(route_conf, consumer_conf)
    core.log.info("route conf: ", core.json.delay_encode(route_conf))
    core.log.info("consumer conf: ", core.json.delay_encode(consumer_conf))

    local flag = tostring(route_conf) .. tostring(consumer_conf)
    local new_conf = merged_route(flag, nil,
                            merge_consumer_route, route_conf, consumer_conf)

    return new_conf, new_conf ~= route_conf
end


function _M.init_worker()
    _M.load()
end


function _M.get(name)
    return local_plugins_hash and local_plugins_hash[name]
end


return _M
