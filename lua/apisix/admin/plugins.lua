local core = require("apisix.core")
local local_plugins = require("apisix.plugin").plugins_hash
local pairs = pairs


local _M = {
    version = 0.1,
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
            local ok, err = plugin_obj.check_schema(plugin_conf)
            if not ok then
                return false, "failed to check the configuration of plugin "
                              .. name .. " err: " .. err
            end
        end
    end

    return true
end


return _M
