local require = require
local core = require("apisix.core")
local pkg_loaded = package.loaded
local sort_tab = table.sort
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local type = type
local local_plugins = core.table.new(32, 0)
local local_plugins_hash = core.table.new(0, 32)
local local_conf


local _M = {
    version = 0.2,
    load_times = 0,
    plugins = local_plugins,
    plugins_hash = local_plugins_hash,
}


local function sort_plugin(l, r)
    return l.priority > r.priority
end


local function load_plugin(name)
    local pkg_name = "apisix.plugins." .. name
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
    core.table.insert(local_plugins, plugin)

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
            load_plugin(name)
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
    return local_plugins
end
_M.load = load



local fetch_api_routes
do
    local routes = {}
function fetch_api_routes()
    core.table.clear(routes)

    for _, plugin in ipairs(_M.plugins) do
        local api_fun = plugin.api
        if api_fun then
            local api_routes = api_fun()
            core.log.debug("feched api routes: ",
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


function _M.merge_service_route(service_conf, route_conf)
    core.log.info("service conf: ", core.json.delay_encode(service_conf))
    -- core.log.info("route conf  : ", core.json.delay_encode(route_conf))

    -- optimize: use LRU to cache merged result
    local new_service_conf

    local changed = false
    if route_conf.value.plugins then
        for name, conf in pairs(route_conf.value.plugins) do
            if not new_service_conf then
                new_service_conf = core.table.deepcopy(service_conf)
            end
            new_service_conf.value.plugins[name] = conf
        end
        changed = true
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
        changed = true
    end

    if route_conf.value.upstream_id then
        if not new_service_conf then
            new_service_conf = core.table.deepcopy(service_conf)
        end
        new_service_conf.value.upstream_id = route_conf.value.upstream_id
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(new_service_conf))
    return new_service_conf or service_conf, changed
end


function _M.init_worker()
    load()
end


function _M.get(name)
    return local_plugins_hash and local_plugins_hash[name]
end


return _M
