local ngx         = ngx
local core        = require("apisix.core")
local plugin_name = "grpc-proxy"
local proto       = require("apisix.plugins.grpc-proxy.proto")
local request     = require("apisix.plugins.grpc-proxy.request")
local response    = require("apisix.plugins.grpc-proxy.response")

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
    local proto_id = conf.proto_id
    if not proto_id then
        ngx.log(ngx.ERR, ("proto id miss: %s"):format(proto_id))
        return
    end

    local p, err = proto.new(proto_id)
    if err then
        ngx.log(ngx.ERR, ("proto load error: %s"):format(err))
        return
    end
    local req = request.new(p)
    err = req:transform(conf.service, conf.method)
    if err then
        ngx.log(ngx.ERR, ("trasnform request error: %s"):format(err))
        return
    end

end


function _M.header_filter(conf, ctx)
    ngx.header["Content-Type"] = "application/json"
end


function _M.body_filter(conf, ctx)
    local proto_id = conf.proto_id
    if not proto_id then
        ngx.log(ngx.ERR, ("proto id miss: %s"):format(proto_id))
        return
    end

    local p, err = proto.new(proto_id)
    if err then
        ngx.log(ngx.ERR, ("proto load error: %s"):format(err))
        return
    end
    local resp = response.new(p)
    err = resp:transform(conf.service, conf.method)
    if err then
        ngx.log(ngx.ERR, ("trasnform response error: %s"):format(err))
        return
    end
end


return _M
