local ngx         = ngx
local core        = require("apisix.core")
local plugin_name = "grpc-transcode"
local proto       = require("apisix.plugins.grpc-transcode.proto")
local request     = require("apisix.plugins.grpc-transcode.request")
local response    = require("apisix.plugins.grpc-transcode.response")


local schema = {
    type = "object",
    additionalProperties = true
}


local _M = {
    version = 0.1,
    priority = 506,
    name = plugin_name,
    schema = schema,
}


function _M.init()
    proto.init()
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("conf: ", core.json.delay_encode(conf))

    local proto_id = conf.proto_id
    if not proto_id then
        core.log.error("proto id miss: ", proto_id)
        return
    end

    local proto_obj, err = proto.fetch(proto_id)
    if err then
        core.log.error("proto load error: ", err)
        return
    end

    local ok, err = request(proto_obj, conf.service, conf.method)
    if not ok then
        core.log.error("trasnform request error: ", err)
        return
    end

    ctx.proto_obj = proto_obj
end


function _M.header_filter(conf, ctx)
    ngx.header["Content-Type"] = "application/json"
    ngx.header["Trailer"] = {"grpc-status", "grpc-message"}
end


function _M.body_filter(conf, ctx)
    local proto_obj = ctx.proto_obj
    if not proto_obj then
        return
    end

    local err = response(proto_obj, conf.service, conf.method)
    if err then
        core.log.error("trasnform response error: ", err)
        return
    end
end


return _M
