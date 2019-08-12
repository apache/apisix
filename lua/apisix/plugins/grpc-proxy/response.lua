local pb = require("pb")
local json = require("cjson")
local util = require("apisix.plugins.grpc-proxy.util")

local _M = {}

_M.new = function(proto)
  local instance = {}
  instance.transform = function(self, service, method)
    local m = util.find_method(proto, service, method)
    if not m then
      return ("2.Undefined service method: %s/%s end."):format(service, method)
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    local buffered = ngx.ctx.buffered
    if not buffered then
      buffered = {}
      ngx.ctx.buffered = buffered
    end
    if chunk ~= "" then
      buffered[#buffered + 1] = chunk
      ngx.arg[1] = nil
    end

    if eof then
      ngx.ctx.buffered = nil
      local buffer = table.concat(buffered)
      if not ngx.req.get_headers()["X-Grpc-Web"] then
        buffer = string.sub(buffer, 6)
      end

      local decoded = pb.decode(m.output_type, buffer)
      local response = json.encode(decoded)
      ngx.arg[1] = response
    end
  end

  return instance
end

return _M
