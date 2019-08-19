local ngx    = ngx
local string = string
local table  = table
local pb     = require("pb")
local bit    = require("bit")
local util   = require("apisix.plugins.grpc-proxy.util")

local _M = {version = 0.1}

function _M.new(proto)
    local instance = {}

    instance.transform = function(self, service, method, default_values)
        local m = util.find_method(proto, service, method)
        if not m then
            return "Undefined service method: " .. service .. "/" .. method
                   .. " end"
        end

        ngx.req.read_body()
        local encoded = pb.encode(m.input_type,
            util.map_message(m.input_type, default_values or {}))
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
        ngx.req.set_uri("/" .. service .. "/" .. method, false)
        ngx.req.set_uri_args({})
        ngx.req.init_body(#message)
        ngx.req.set_body_data(message)
        return nil
    end

    return instance
end


return _M
