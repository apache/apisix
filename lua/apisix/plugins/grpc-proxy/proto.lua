local protoc   = require("protoc")
local lrucache = require("apisix.core.lrucache")
local config   = require("apisix.core.config_etcd")
local schema   = require("apisix.core.schema")
local protos


local function protos_arrange()
    local result = {}

    if protos.values == nil then
        return result
    end

    for _, proto in ipairs(protos.values) do
        local id = proto.value.id
        result[id] = proto.value.content
    end

    return result
end


local _M = {}

_M.new = function(proto_id)
    local cache   = lrucache.global("/proto", protos.conf_version, protos_arrange)
    local content = cache[proto_id]

    if not content then
        ngx.log(ngx.ERR, "failed to find proto by id: " .. proto_id)
        return 
    end

    local _p = protoc.new()
    _p:load(content)

    local instance = {}
    instance.get_loaded_proto = function()
        return _p.loaded
    end
    return instance
end


_M.init_worker = function()
    local err
    protos, err = config.new("/proto",
                        {
                            automatic = true,
                            item_schema = schema.proto
                        })
    if not protos then
        ngx.log(ngx.ERR, "failed to create etcd instance for fetching protos: " .. err)
        return
    end
end

return _M
