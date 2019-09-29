local limit_local_new = require("resty.limit.count").new
local limit_redis_new = require("apisix.plugins.limit-count.redis").new
local core = require("apisix.core")
local plugin_name = "limit-count"


local schema = {
    type = "object",
    properties = {
        count = {type = "integer", minimum = 0},
        time_window = {type = "integer",  minimum = 0},
        key = {
            type = "string",
            enum = {"remote_addr", "server_addr", "http_x_real_ip",
                    "http_x_forwarded_for"},
        },
        rejected_code = {type = "integer", minimum = 200, maximum = 600},
        policy = {
            type = "string",
            enum = {"local", "redis"},
        },
        redis = {
            type = "object",
            properties = {
                host = {
                    type = "string", minLength = 2
                },
                port = {
                    type = "integer", minimum = 1
                },
                timeout = {
                    type = "integer", minimum = 1
                },
            },
            required = {"host"},
        },
    },
    additionalProperties = false,
    required = {"count", "time_window", "key", "rejected_code"},
}


local _M = {
    version = 0.1,
    priority = 1002,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.policy then
        conf.policy = "local"
    end

    if conf.policy == "redis" then
        if not conf.redis then
            return false, "missing valid redis options"
        end
    end

    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-count plugin instance")

    if not conf.policy or conf.policy == "local" then
        return limit_local_new("plugin-" .. plugin_name, conf.count,
                               conf.time_window)
    end

    if conf.policy == "redis" then
        return limit_redis_new(conf.count, conf.time_window, conf.redis)
    end

    return nil
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local lim, err = core.lrucache.plugin_ctx(plugin_name, ctx,
                                              create_limit_obj, conf)
    if not lim then
        core.log.error("failed to fetch limit.count object: ", err)
        return 500
    end

    local key = (ctx.var[conf.key] or "") .. ctx.conf_type .. ctx.conf_version
    core.log.info("limit key: ", key)

    local delay, remaining = lim:incoming(key, true)
    if not delay then
        local err = remaining
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    core.response.set_header("X-RateLimit-Limit", conf.count,
                             "X-RateLimit-Remaining", remaining)
end


return _M
