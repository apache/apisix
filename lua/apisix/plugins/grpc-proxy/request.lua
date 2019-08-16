local pb = require("pb")
local bit = require("bit")
local util = require("apisix.plugins.grpc-proxy.util")

local _M = {}

_M.new = function(proto)
    local instance = {}

    instance.transform = function(self, service, method, default_values)
        local m = util.find_method(proto, service, method)
        if not m then
            return ("1.Undefined service method: %s/%s end."):format(service, method)
        end

        ngx.req.read_body()
        local encoded = pb.encode(m.input_type, util.map_message(m.input_type, default_values or {}))
        local size = string.len(encoded)
        local prefix = {
            string.char(0),
            string.char(bit.band(bit.rshift(size, 24), 0xFF)),
            string.char(bit.band(bit.rshift(size, 16), 0xFF)),
            string.char(bit.band(bit.rshift(size, 8), 0xFF)),
            string.char(bit.band(size, 0xFF))
        }

        local message = table.concat(prefix, "") .. encoded

        ngx.req.set_method(ngx.HTTP_POST)
        ngx.req.set_uri(("/%s/%s"):format(service, method), false)
        ngx.req.set_uri_args({})
        ngx.req.init_body(string.len(message))
        ngx.req.set_body_data(message)
        return nil
    end

    return instance
end

return _M