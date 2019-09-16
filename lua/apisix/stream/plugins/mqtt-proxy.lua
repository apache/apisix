local core      = require("apisix.core")
local balancer  = require("ngx.balancer")
local ngx_exit  = ngx.exit
local str_byte  = string.byte
local str_sub   = string.sub


local schema = {
    type = "object",
    properties = {
        protocol_name = {type = "string"},
        protocol_level = {type = "integer"},
        upstream = {
            type = "object",
            properties = {
                ip = {type = "string"},
                port = {type = "number"},
            }
        }
    },
    required = {"protocol_name", "protocol_level", "upstream"},
}


local plugin_name = "mqtt-proxy"


local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


local function parse_mqtt(data)
    local res = {}
    res.packet_type_flags_byte = str_byte(data, 1, 1)
    if res.packet_type_flags_byte < 16 or res.packet_type_flags_byte > 32 then
        return nil, "Received unexpected MQTT packet type+flags: "
                    .. res.packet_type_flags_byte
    end

    local parsed_pos = 1
    res.remaining_len = 0
    local multiplier = 1
    for i = 2, 5 do
        parsed_pos = i
        local byte = str_byte(data, i, i)
        res.remaining_len = res.remaining_len + bit.band(byte, 127) * multiplier
        multiplier = multiplier * 128
        if bit.band(byte, 128) == 0 then
            break
        end
    end

    local protocol_len = str_byte(data, parsed_pos + 1, parsed_pos + 1) * 256
                         + str_byte(data, parsed_pos + 2, parsed_pos + 2)
    parsed_pos = parsed_pos + 2
    res.protocol = str_sub(data, parsed_pos + 1, parsed_pos + protocol_len)
    parsed_pos = parsed_pos + protocol_len

    res.protocol_ver = str_byte(data, parsed_pos + 1, parsed_pos + 1)
    parsed_pos = parsed_pos + 1
    if res.protocol_ver == 4 then
        parsed_pos = parsed_pos + 3
    elseif res.protocol_ver == 5 then
        parsed_pos = parsed_pos + 9
    end

    local client_id_len = str_byte(data, parsed_pos + 1, parsed_pos + 1) * 256
                          + str_byte(data, parsed_pos + 2, parsed_pos + 2)
    parsed_pos = parsed_pos + 2

    if parsed_pos + client_id_len > #data then
        res.expect_len = parsed_pos + client_id_len
        return res
    end

    res.client_id = str_sub(data, parsed_pos + 1, parsed_pos + client_id_len)
    parsed_pos = parsed_pos + client_id_len

    res.expect_len = parsed_pos
    return res
end


function _M.preread(conf, ctx)
    core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf))
    -- core.log.warn(" ctx: ", core.json.encode(ctx, true))
    local sock = ngx.req.socket()
    local data, err = sock:peek(16)
    if not data then
        core.log.error("failed to read first 16 bytes: ", err)
        return ngx_exit(1)
    end

    local res, err = parse_mqtt(data)
    if not res then
        core.log.error("failed to parse the first 16 bytes: ", err)
        return ngx_exit(1)
    end

    if res.expect_len > #data then
        data, err = sock:peek(res.expect_len)
        if not data then
            core.log.error("failed to read ", res.expect_len, " bytes: ", err)
            return ngx_exit(1)
        end

        res = parse_mqtt(data)
        if res.expect_len > #data then
            core.log.error("failed to parse mqtt request, expect len: ",
                           res.expect_len, " but got ", #data)
            return ngx_exit(1)
        end
    end

    if res.protocol and res.protocol ~= conf.protocol_name then
        core.log.error("expect protocol name: ", conf.protocol_name
                       ", but got ", res.protocol)
        return ngx_exit(1)
    end

    if res.protocol_ver and res.protocol_ver ~= conf.protocol_level then
        core.log.error("expect protocol level: ", conf.protocol_level
                       ", but got ", res.protocol_ver)
        return ngx_exit(1)
    end

    core.log.info("mqtt client id: ", res.client_id)
end


function _M.log(conf, ctx)
    core.log.info("plugin log phase, conf: ", core.json.encode(conf))
end


function _M.balancer(conf, ctx)
    core.log.info("plugin balancer phase, conf: ", core.json.encode(conf))
    -- ctx.balancer_name = plugin_name
    local up = conf.upstream
    ctx.balancer_name = plugin_name

    local ok, err = balancer.set_current_peer(up.ip, up.port)
    if not ok then
        core.log.error("failed to set server peer: ", err)
        return ngx_exit(1)
    end
end


return _M
