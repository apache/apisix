local core = require("apisix.core")

local schema = {
    type = "object",
    properties = {
        vars = {
            type = "object",
            description = "Key-value pairs for the variables to register",
            additionalProperties = {
                type = "string"
            }
        }
    },
    required = { "vars" },
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
    local vars = conf.vars
    for k, v in pairs(vars) do
        ctx.var[k] = v
    end
end

return _M
