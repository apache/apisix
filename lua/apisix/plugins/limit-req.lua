local limit_req_new = require("resty.limit.req").new
local core = require("apisix.core")
local plugin_name = "limit-req"
local sleep = ngx.sleep


local schema = {
    type = "object",
    properties = {
        rate = {type = "integer", minimum = 0},
        burst = {type = "integer",  minimum = 0},
        key = {type = "string", enum = {"remote_addr"}},
        rejected_code = {type = "integer", minimum = 200},
    },
    required = {"rate", "burst", "key", "rejected_code"}
}


local _M = {
    version = 0.1,
    priority = 1001,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-req plugin instance")
    return limit_req_new("plugin-limit-req", conf.rate, conf.burst)
end


function _M.access(conf, ctx)
    local lim, err = core.lrucache.plugin_ctx(plugin_name, ctx,
                                               create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        return 500
    end

    local key = ctx.var[conf.key]
    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end

return _M
