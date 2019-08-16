local core = require("apisix.core")
local protoc = require("protoc")
local util = require("apisix.plugins.grpc-proxy.util")


local _M = {}

_M.new = function(proto_id)
  local _p = protoc.new()

    local key = "/proto/" .. proto_id
    local res, err = core.etcd.get(key)

    local proto_obj = res.body.node.value

  -- local err
  -- proto_etcd, err = core.config.new("/proto", {
  --                             automatic = true,
  --                             item_schema = core.schema.proto
  --                         })
  -- if not proto_etcd then
  --     ngx.log(ngx.ERR, "failed to create etcd instance for fetching proto:" .. err)
  --     return
  -- end

  --local proto_obj = proto_etcd:get(tostring(proto_id))
  if not proto_obj then
      ngx.log(ngx.ERR, "failed to find proto by id: " .. proto_id)
      return 
  end


  _p:load(proto_obj.content)

  local instance = {}
  instance.get_loaded_proto = function()
    return _p.loaded
  end
  return instance
end

return _M
