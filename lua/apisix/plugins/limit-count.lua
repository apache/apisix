local limit_count_new = require("resty.limit.count").new
local core = require("apisix.core")
local plugin_name = "limit-count"


local _M = {
    version = 0.1,
    priority = 1002,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_args(conf)
    -- todo: check arguments
    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-count plugin instance")
    return limit_count_new("plugin-limit-count", conf.count, conf.time_window)
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local limit = core.lrucache.plugin_ctx(plugin_name, ctx,
                                           create_limit_obj, conf)

    if conf.key ~= 'remote_addr' then
        core.log.error("only support 'remote_addr' as key now")
    end
    local key = ctx.var[conf.key]
    local rejected_code = conf.rejected_code or ngx.HTTP_SERVICE_UNAVAILABLE

    local delay, remaining = limit:incoming(key, true)
    if not delay then
        local err = remaining
        if err == "rejected" then
            return rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return ngx.HTTP_INTERNAL_SERVER_ERROR
    end

    core.response.set_header("X-RateLimit-Limit", conf.count,
                             "X-RateLimit-Remaining", remaining)
end


return _M
