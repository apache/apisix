local core = require("apisix.core")

local plugin_name = "limit-monthly-cu"

local schema = {
    type = "object",
    properties = {
        monthly_quota = { type = "string", default = "$monthly_quota" },
        monthly_used = { type = "string", default = "$monthly_used" },
    },
    required = { "monthly_quota", "monthly_used" }
}

local _M = {
    version = 0.1,
    priority = 1011,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.monthly_quota then
        if conf.monthly_quota:byte(1, 1) ~= string.byte("$") then
            return false, "monthly_quota is a variable, it must start with $"
        end
    end

    if conf.monthly_used then
        if conf.monthly_used:byte(1, 1) ~= string.byte("$") then
            return false, "monthly_used is a variable, it must start with $"
        end
    end
    return true
end

function _M.access(conf, ctx)
    local monthly_quota = tonumber(ngx.ctx[conf.monthly_quota:sub(2)])
    local monthly_used = tonumber(ngx.ctx[conf.monthly_used:sub(2)])

    if monthly_quota <= monthly_used then
        return 429, { error_msg = "quota exceeded" }
    end
end

return _M
