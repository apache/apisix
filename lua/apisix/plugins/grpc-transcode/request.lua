
local util   = require("apisix.plugins.grpc-transcode.util")
local core   = require("apisix.core")
local pb     = require("pb")
local bit    = require("bit")
local ngx    = ngx
local string = string
local table  = table


return function (proto, service, method, default_values)
    core.log.info("proto: ", core.json.delay_encode(proto, true))
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "Undefined service method: " .. service .. "/" .. method
                      .. " end"
    end

    ngx.req.read_body()
    local encoded = pb.encode(m.input_type,
        util.map_message(m.input_type, default_values or {}))

    if not encoded then
        return false, "failed to encode request data to protobuf"
    end

    local size = #encoded
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
    ngx.req.set_body_data(message)
    return true
end
