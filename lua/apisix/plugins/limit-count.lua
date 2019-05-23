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
    local limit_ins = core.lrucache.plugin_ctx(plugin_name, ctx,
                                               create_limit_obj, conf)

    local key = core.ctx.get_var(ctx, conf.key)
    if not key or key == "" then
        key = ""
        core.log.warn("fetched empty string value as key to limit the request ",
                      "maybe wrong, please pay attention to this.")
    end

    local delay, remaining = limit_ins:incoming(key, true)
    if not delay then
        local err = remaining
        if err == "rejected" then
            return core.response.say(conf.rejected_code)
        end

        core.log.error("failed to limit req: ", err)
        return core.response.say(500)
    end

    core.response.set_header("X-RateLimit-Limit", conf.count)
    core.response.set_header("X-RateLimit-Remaining", remaining)

    core.log.info("hit limit-count access")
end


return _M
