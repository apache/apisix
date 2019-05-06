local require = require
local config = require("apimeta.core.config")
local typeof = require("apimeta.core.typeof")
local log = require("apimeta.core.log")

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
        return false, "failed to read plugin list form local file"
    end

    -- todo: table.new
    local plugins = {}
    for _, name in ipairs(plugin_names) do
        local ok, plugin = pcall(require, "apimeta.plugins." .. name)
        if not ok then
            log.error("failed to load plugin ", name, " err: ", plugin)

        else
            if not plugin.name then
                plugin.name = name
            end
            insert_tab(plugins, plugin)
        end
    end

    -- sort by plugin's priority
    if #plugins > 1 then
        sort_tab(plugins, sort_plugin)
    end

    return plugins
end


return _M
