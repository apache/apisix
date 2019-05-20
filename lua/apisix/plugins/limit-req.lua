local limit_req = require("resty.limit.req")
local core = require("apisix.core")
-- todo: support to config it in yaml
local cache = core.global_lru.fetch("/plugin/limit-req", 200)


local _M = {
    version = 0.1,
    priority = 1001,        -- TODO: add a type field, may be a good idea
    name = "limit-req",
}


function _M.check_args(conf)
    return true
end


function _M.access(conf, api_ctx)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id
    -- core.log.warn("key: ", key, " conf: ", core.json.encode(conf))

    local limit_ins = cache:get(key)
    if not limit_ins or limit_ins.version ~= api_ctx.conf_version then
        limit_ins = limit_req.new("plugin-limit-req", conf.rate, conf.burst)
        cache:set(key, limit_ins)
    end

    key = core.ctx.get(api_ctx, conf.key)

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
