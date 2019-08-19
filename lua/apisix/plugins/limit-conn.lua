local limit_conn_new = require("resty.limit.conn").new
local core = require("apisix.core")
local sleep = ngx.sleep
local plugin_name = "limit-conn"


local schema = {
    type = "object",
    properties = {
        conn = {type = "integer", minimum = 0},
        burst = {type = "integer",  minimum = 0},
        default_conn_delay = {type = "number", minimum = 0},
        key = {type = "string", enum = {"remote_addr", "server_addr"}},
        rejected_code = {type = "integer", minimum = 200},
    },
    required = {"conn", "burst", "default_conn_delay", "key", "rejected_code"}
}


local _M = {
    version = 0.1,
    priority = 1003,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

local function create_limit_obj(conf)
    core.log.info("create new limit-conn plugin instance")
    return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst,
                          conf.default_conn_delay)
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local lim, err = core.lrucache.plugin_ctx(plugin_name, ctx,
                                              create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.conn object: ", err)
        return 500
    end

    local key = (ctx.var[conf.key] or "") .. ctx.conf_type .. ctx.conf_version
    local rejected_code = conf.rejected_code

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    if lim:is_committed() then
        ctx.limit_conn = lim
        ctx.limit_conn_key = key
        ctx.limit_conn_delay = delay
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end


function _M.log(conf, ctx)
    local lim = ctx.limit_conn
    if lim then
        local latency
        if ctx.proxy_passed then
            latency = ctx.var.upstream_response_time
        else
            latency = ctx.var.request_time - ctx.limit_conn_delay
        end

        local key = ctx.limit_conn_key
        local conn, err = lim:leaving(key, latency)
        if not conn then
            core.log.error("failed to record the connection leaving request: ",
                           err)
            return
        end
    end
end


return _M
