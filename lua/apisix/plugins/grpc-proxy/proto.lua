local core     = require("apisix.core")
local protoc   = require("protoc")
local lrucache = require("apisix.core.lrucache")
local config   = require("apisix.core.config_etcd")
local schema   = require("apisix.core.schema")
local protos


local function protos_arrange(proto_id)
    if protos.values == nil then
        return nil
    end

    ngx.log(ngx.ERR, "load proto")

    local content
    for _, proto in ipairs(protos.values) do
        if proto_id == proto.value.id then
            content = proto.value.content
            break
        end
    end

    if not content then
        ngx.log(ngx.ERR, "failed to find proto by id: " .. proto_id)
        return
    end

    local _p = protoc.new()
    _p:load(content)

    return _p.loaded
end


local _M = {version = 0.1}


function _M.new(proto_id)
    return lrucache.global("/protoc", protos.conf_version, protos_arrange, proto_id)
end


function _M.init()
    local err
    protos, err = config.new("/proto", {
        automatic = true,
        item_schema = schema.proto
    })
    if not protos then
        core.log.error("failed to create etcd instance for fetching protos: " .. err)
        return
    end
end


return _M
