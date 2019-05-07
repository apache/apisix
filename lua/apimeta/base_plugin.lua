local require = require
local config = require("apimeta.core.config")
local typeof = require("apimeta.core.typeof")
local log = require("apimeta.core.log")
local new_tab = require("table.new")
local pkg_loaded = package.loaded
local insert_tab = table.insert
local sort_tab = table.sort
local tostring = tostring
local pcall = pcall
local ipairs = ipairs
local pairs = pairs


local _M = {
    log = log,
}


function _M.check_args(args, scheme)
    for k, v in pairs(scheme) do
        if not typeof[v](args[k]) then
            return nil, "args." .. k .. " expect " .. v .. " value but got: ["
                        .. tostring(args[k]) .. "]"
        end
    end

    return true
end

local function sort_plugin(l, r)
    return l.priority > r.priority
end

function _M.load()
    local plugin_names = config.read().plugins
    if not plugin_names then
        return nil, "failed to read plugin list form local file"
    end

    local plugins = new_tab(#plugin_names, 0)
    for _, name in ipairs(plugin_names) do
        local pkg_name = "apimeta.plugins." .. name
        pkg_loaded[pkg_name] = nil

        local ok, plugin = pcall(require, pkg_name)
        if not ok then
            log.error("failed to load plugin ", name, " err: ", plugin)

        elseif not plugin.priority then
            log.error("invalid plugin", name, ", missing field: priority")

        elseif not plugin.check_args then
            log.error("invalid plugin", name, ", missing method: check_args")

        elseif not plugin.version then
            log.error("invalid plugin", name, ", missing field: version")

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

function _M.filter_plugin(user_plugins, local_supported_plugins)
    -- todo: reuse table
    local plugins = new_tab(#local_supported_plugins * 2, 0)

    for _, plugin_obj in ipairs(local_supported_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugins[name]

        if plugin_conf then
            insert_tab(plugins, plugin_obj)
            insert_tab(plugins, plugin_conf)
        end
    end

    return plugins
end


return _M
