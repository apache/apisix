local require = require
local core = require("apisix.core")
local pkg_loaded = package.loaded
local insert_tab = table.insert
local sort_tab = table.sort
local pcall = pcall
local ipairs = ipairs
local type = type


local _M = {version = 0.1}


local function sort_plugin(l, r)
    return l.priority >= r.priority
end


function _M.load()
    local plugin_names = core.config.local_conf().plugins
    if not plugin_names then
        return nil, "failed to read plugin list form local file"
    end

    local plugins = core.table.new(#plugin_names, 0)
    for _, name in ipairs(plugin_names) do
        local pkg_name = "apisix.plugins." .. name
        pkg_loaded[pkg_name] = nil

        local ok, plugin = pcall(require, pkg_name)
        if not ok then
            core.log.error("failed to load plugin ", name, " err: ", plugin)

        elseif not plugin.priority then
            core.log.error("invalid plugin", name, ", missing field: priority")

        elseif not plugin.check_args then
            core.log.error("invalid plugin", name, ", missing method: check_args")

        elseif not plugin.version then
            core.log.error("invalid plugin", name, ", missing field: version")

        else
            plugin.name = name
            insert_tab(plugins, plugin)
        end
    end

    -- sort by plugin's priority
    if #plugins > 1 then
        sort_tab(plugins, sort_plugin)
    end

    return plugins
end


function _M.filter_plugin(user_routes, local_supported_plugins)
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


return _M
