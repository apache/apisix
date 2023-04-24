local core = require("apisix.core")

local schema = {
    type = "object",
    description = "Key-value pairs for the variables to register",
    additionalProperties = true
}

local plugin_name = "custom-ctx-var"

local _M = {
    version = 0.1,
    priority = 24000,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

function _M.access(conf)
    local route_id = core.ctx.route_id
    core.log.info("route_id: ", route_id)

    for k, v in pairs(conf) do
        local var_name = route_id .. k
        core.ctx.register_var(var_name, function() return v end)
    end
end

return _M
