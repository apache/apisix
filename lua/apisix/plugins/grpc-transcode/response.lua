local util   = require("apisix.plugins.grpc-transcode.util")
local core   = require("apisix.core")
local pb     = require("pb")
local ngx    = ngx
local string = string
local table  = table


return function(proto, service, method)
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "2.Undefined service method: " .. service .. "/" .. method
                      .. " end."
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    local buffered = ngx.ctx.buffered
    if not buffered then
        buffered = {}
        ngx.ctx.buffered = buffered
    end

    if chunk ~= "" then
        core.table.insert(buffered, chunk)
        ngx.arg[1] = nil
    end

    if not eof then
        return
    end

    ngx.ctx.buffered = nil
    local buffer = table.concat(buffered)
    if not ngx.req.get_headers()["X-Grpc-Web"] then
        buffer = string.sub(buffer, 6)
    end

    local decoded = pb.decode(m.output_type, buffer)
    if not decoded then
        ngx.arg[1] = "failed to decode response data by protobuf"
        return
    end

    local response, err = core.json.encode(decoded)
    if not response then
        core.log.error("failed to call json_encode data: ", err)
        response = "failed to json_encode response body"
    end

    ngx.arg[1] = response
end
