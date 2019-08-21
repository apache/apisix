local core   = require("apisix.core")
local protoc = require("protoc")
local ipairs = ipairs
local protos


local lrucache_proto = core.lrucache.new({
    ttl = 300, count = 100
})


local function create_proto_obj(proto_id)
    if protos.values == nil then
        return nil
    end

    local content
    for _, proto in ipairs(protos.values) do
        if proto_id == proto.value.id then
            content = proto.value.content
            break
        end
    end

    if not content then
        return nil, "failed to find proto by id: " .. proto_id
    end

    local _p  = protoc.new()
    local res = _p:load(content)

    if not res or not _p.loaded then
        return nil, "failed to load proto content"
    end


    return _p.loaded
end


local _M = {version = 0.1}


function _M.fetch(proto_id)
    return lrucache_proto(proto_id, protos.conf_version,
                          create_proto_obj, proto_id)
end


function _M.init()
    local err
    protos, err = core.config.new("/proto", {
        automatic = true,
        item_schema = core.schema.proto
    })
    if not protos then
        core.log.error("failed to create etcd instance for fetching protos: ",
                       err)
        return
    end
end


return _M
