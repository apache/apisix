local core = require("apisix.core")
local local_plugins = require("apisix.plugin").plugins_hash
local pairs = pairs
local pcall = pcall
local require = require


local _M = {
    version = 0.1,
}


local disable_schema = {
    type = "object",
    properties = {
        disable = {type = "boolean", enum={true}}
    },
    required = {"disable"}
}


function _M.check_schema(plugins_conf)
    for name, plugin_conf in pairs(plugins_conf) do
        core.log.info("check plugin scheme, name: ", name, ", configurations: ",
                      core.json.delay_encode(plugin_conf, true))
        local plugin_obj = local_plugins[name]
        if not plugin_obj then
            return false, "unknow plugin [" .. name .. "]"
        end

        if plugin_obj.check_schema then
            local ok = core.schema.check(disable_schema, plugin_conf)
            if not ok then
                local ok, err = plugin_obj.check_schema(plugin_conf)
                if not ok then
                    return false, "failed to check the configuration of plugin "
                                  .. name .. " err: " .. err
                end
            end
        end
    end

    return true
end


function _M.get(name)
    local plugin_name = "apisix.plugins." .. name

    local ok, plugin = pcall(require, plugin_name)
    if not ok then
        core.log.warn("failed to load plugin [", name, "] err: ", plugin)
        return 400, {error_msg = "failed to load plugin " .. name}
    end

    local json_schema = plugin.schema
    if not json_schema then
        return 400, {error_msg = "not found schema"}
    end

    return 200, json_schema
end


return _M
