local require = require
local core = require("apisix.core")
local pkg_loaded = package.loaded
local sort_tab = table.sort
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local type = type
local local_plugins = core.table.new(10, 0)
local local_plugins_hash = core.table.new(10, 0)


local _M = {
    version = 0.1,
    load_times = 0,
    plugins = local_plugins,
    plugins_hash = local_plugins_hash,
}


local function sort_plugin(l, r)
    return l.priority >= r.priority
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

    local local_conf = core.config.local_conf()
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

    for _, plugin in ipairs(local_plugins) do
        local_plugins_hash[plugin.name] = plugin
    end

    _M.load_times = _M.load_times + 1
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

    return plugins
end


function _M.merge_service_route(service_conf, route_conf)
    -- core.log.info("service conf: ", core.json.delay_encode(service_conf))
    -- core.log.info("route conf  : ", core.json.delay_encode(route_conf))
    local changed = false
    if route_conf.value.plugins then
        for name, conf in pairs(route_conf.value.plugins) do
            service_conf.value.plugins[name] = conf
        end
        changed = true
    end

    if route_conf.value.upstream then
        service_conf.value.upstream = route_conf.value.upstream
        changed = true
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(service_conf))
    return service_conf, changed
end


function _M.init_worker()
    load()
end


return _M
