local limit_req = require("resty.limit.req")
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
    core.log.info("create new plugin ins")
    return limit_req.new("plugin-limit-req",
                         conf.rate, conf.burst)
end


function _M.access(conf, api_ctx)
    -- todo: support to config it in yaml
    local limit_ins = core.lrucache.plugin_ctx(plugin_name, api_ctx,
                                               create_limit_obj, conf)

    local key = core.ctx.get(api_ctx, conf.key)
    if not key or key == "" then
        key = ""
        core.log.warn("fetched empty string value as key to limit the request ",
                      "maybe wrong, please pay attention to this.")
    end

    local delay, err = limit_ins:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return core.resp(conf.rejected_code)
        end

        core.log.error("failed to limit req: ", err)
        return core.resp(500)
    end

    core.log.info("hit limit-req access")
end


return _M
