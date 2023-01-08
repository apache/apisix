local plugin_name = "limit-monthly-cu"

local schema = {
    type = "object",
    properties = {
        monthly_quota = { type = "integer", minimum = 0, default = 100000 },
        monthly_used = { type = "integer", minimum = 0, default = 0 },
    },
    required = { "monthly_quota", "monthly_used" }
}

local _M = {
    version = 0.1,
    priority = 1011,
    name = plugin_name,
    schema = schema,
}


function _M.access(conf, ctx)
    if conf.monthly_quota <= conf.monthly_used then
        return 429, { error_msg = "quota exceeded" }
    end
end

return _M
