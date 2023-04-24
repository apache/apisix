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

function _M.access(conf, ctx)
    for k, v in pairs(conf) do
        -- if k is subdomain, add route_id prefix to avoid conflicts
        -- format: route_id.subdomain
        if k == "subdomain" then
            core.ctx.register_var("route_id." .. k, function() return v end)
        else
            core.ctx.register_var(k, function() return v end)
        end
    end
end

return _M
