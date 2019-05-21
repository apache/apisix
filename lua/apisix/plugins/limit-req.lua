local limit_req_new = require("resty.limit.req").new
local core = require("apisix.core")
local plugin_name = "limit-req"


local _M = {
    version = 0.1,
    priority = 1001,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_args(conf)
    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-req plugin instance")
    return limit_req_new("plugin-limit-req", conf.rate, conf.burst)
end


function _M.access(conf, ctx)
    local limit_ins = core.lrucache.plugin_ctx(plugin_name, ctx,
                                               create_limit_obj, conf)

    local key = core.ctx.get(ctx, conf.key)
    if not key or key == "" then
        key = ""
        core.log.warn("fetched empty string value as key to limit the request ",
                      "maybe wrong, please pay attention to this.")
    end

    local delay, err = limit_ins:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return core.resp.say(conf.rejected_code)
        end

        core.log.error("failed to limit req: ", err)
        return core.resp.say(500)
    end

    core.log.info("hit limit-req access")
end


return _M
