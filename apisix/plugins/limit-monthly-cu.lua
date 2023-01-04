local core = require "apisix.core"
local consumer = require("apisix.consumer")


local plugin_name = "limit-monthly-cu"

local consumer_schema = {
    type = "object",
    properties = {
        labels = {
            type = "object",
            properties = {
                monthly_quota = { type = "string" }, -- can't set to numbers when calling admin API
                monthly_used = { type = "string" },
            },
            required = { "monthly_quota", "monthly_used" },
        },
    },
}

local _M = {
    version = 0.1,
    priority = 1011,
    name = plugin_name,
    schema = {},
    consumer_schema = consumer_schema,
}

function _M.check_schema(conf, schema_type)
    local ok, err
    if schema_type == core.schema.TYPE_CONSUMER then
        ok, err = core.schema.check(consumer_schema, conf)
        -- else
        --     ok, err = core.schema.check(schema, conf)
    end

    if not ok then
        return false, err
    end

    return true
end

function _M.access(conf, ctx)
    -- Fetch the consumer
    local username = consumer.username
    local lables = consumer.labels
    core.log.warn("username: ", username)
    core.log.warn("labels: ", lables)

    -- Fetch the monthly quota and usage from the consumer's labels
    local labels = consumer.labels
    local monthly_quota = tonumber(labels.monthly_quota)
    local monthly_used = tonumber(labels.monthly_used)

    -- If the monthly usage exceeds the quota, return a 429 error
    if monthly_quota <= monthly_used then
        return 429, { error_msg = "quota exceeded" }
    end
end

return _M
