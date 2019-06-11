local require = require
local core = require("apisix.core")
local pkg_loaded = package.loaded
local insert_tab = table.insert
local sort_tab = table.sort
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local type = type
local local_supported_plugins = {}


local _M = {
    version = 0.1,
    load_times = 0,
    plugins = local_supported_plugins,
}


local function sort_plugin(l, r)
    return l.priority >= r.priority
end


local function load()
    core.table.clear(local_supported_plugins)

    local plugin_names = core.config.local_conf().plugins
    if not plugin_names then
        return nil, "failed to read plugin list form local file"
    end

    for _, name in ipairs(plugin_names) do
        local pkg_name = "apisix.plugins." .. name
        pkg_loaded[pkg_name] = nil

        local ok, plugin = pcall(require, pkg_name)
        if not ok then
            core.log.error("failed to load plugin ", name, " err: ", plugin)

        elseif not plugin.priority then
            core.log.error("invalid plugin", name, ", missing field: priority")

        elseif not plugin.check_args then
            core.log.error("invalid plugin", name,
                           ", missing method: check_args")

        elseif not plugin.version then
            core.log.error("invalid plugin", name, ", missing field: version")

        else
            plugin.name = name
            insert_tab(local_supported_plugins, plugin)
        end

        if plugin.init then
            plugin.init()
        end
    end

    -- sort by plugin's priority
    if #local_supported_plugins > 1 then
        sort_tab(local_supported_plugins, sort_plugin)
    end

    _M.load_times = _M.load_times + 1
    return local_supported_plugins
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
            for _, route in ipairs(api_routes) do
                core.table.insert(routes, {route.methods, route.uri,
                                           route.handler})
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


function _M.filter(user_routes)
    -- todo: reuse table
    local plugins = core.table.new(#local_supported_plugins * 2, 0)
    local user_plugin_conf = user_routes.value.plugin_config

    for _, plugin_obj in ipairs(local_supported_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) == "table" then
            insert_tab(plugins, plugin_obj)
            insert_tab(plugins, plugin_conf)
        end
    end

    return plugins
end


function _M.merge_service_route(service_conf, route_conf)
    local changed = false
    if route_conf.value.plugin_config and
       core.table.nkeys(route_conf.value.plugin_config) then
        for name, conf in pairs(route_conf.value.plugin_config) do
            service_conf.value.plugin_config[name] = conf
        end
        changed = true
    end

    if route_conf.upstream and core.table.nkeys(route_conf.upstream) then
        service_conf.upstream = route_conf.upstream
        changed = true
    end

    route_conf.service = service_conf.value

    return service_conf, changed
end


return _M
