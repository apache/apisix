local require = require
local core = require("apisix.core")
local pairs = pairs
local str_format = string.format
local rshift = bit.rshift
local band = bit.band
local char = string.char
local tostring = tostring
local ngx = ngx
local type = type
local plugin_name = "http-dubbo"

local schema = {
    type = "object",
    properties = {
        service_name = {
            type = "string",
            minLength = 1,
        },
        service_version = {
            type = "string",
            pattern = [[^\d+\.\d+\.\d+]],
        },
        method = {
            type = "string",
            minLength = 1,
        },
        params_type_desc = {
            type = "string",
            minLength = 1,
        },
        serialization_header_key = {
            type = "string"
        },
        serialized = {
            type = "boolean",
            default = false
        }
    },
    required = { "service_name", "method", "params_type_desc" },
}

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function str_int32(int)
    return char(band(rshift(int, 24), 0xff),
            band(rshift(int, 16), 0xff),
            band(rshift(int, 8), 0xff),
            band(int, 0xff))
end

local function parse_dubbo_header(header)
    for i = 1, 16 do
        local currentByte = header:byte(i)
        if not currentByte then
            return nil
        end
    end

    local magic_number = str_format("%04x", header:byte(1) * 256 + header:byte(2))
    local message_flag = header:byte(3)
    local status = header:byte(4)
    local request_id = 0
    for i = 5, 12 do
        request_id = request_id * 256 + header:byte(i)
    end

    local byte13Val = header:byte(13) * 256 * 256 * 256
    local byte14Val = header:byte(14) * 256 * 256
    local data_length = byte13Val + byte14Val + header:byte(15) * 256 + header:byte(16)

    local is_request = bit.band(bit.rshift(message_flag, 7), 0x01) == 1 and 1 or 0
    local is_two_way = bit.band(bit.rshift(message_flag, 6), 0x01) == 1 and 1 or 0
    local is_event = bit.band(bit.rshift(message_flag, 5), 0x01) == 1 and 1 or 0

    return {
        magic_number = magic_number,
        message_flag = message_flag,
        is_request = is_request,
        is_two_way = is_two_way,
        is_event = is_event,
        status = status,
        request_id = request_id,
        data_length = data_length
    }
end

local function string_to_json_string(str)
    local result = "\""
    for i = 1, #str do
        local byte = core.string.sub(str, i, i)
        if byte == "\\" then
            result = result .. "\\\\"
        elseif byte == "\n" then
            result = result .. "\\n"
        elseif byte == "\t" then
            result = result .. "\\t"
        elseif byte == "\r" then
            result = result .. "\\r"
        elseif byte == "\b" then
            result = result .. "\\b"
        elseif byte == "\f" then
            result = result .. "\\f"
        elseif byte == "\"" then
            result = result .. "\\\""
        else
            result = result .. byte
        end
    end
    return result .. "\""
end

local function get_dubbo_request(conf, ctx)
    -- use dubbo and fastjson
    local first_byte4 = "\xda\xbb\xc6\x00"

    local requestId = "\x00\x00\x00\x00\x00\x00\x00\x01"
    local version = "\"2.0.2\"\n"
    local service = "\"" .. conf.service_name .. "\"" .. "\n"

    local service_version
    if not conf.service_version then
        service_version = "0.0.0"
    else
        service_version = conf.service_version
    end
    service_version = "\"" .. service_version .. "\"" .. "\n"
    local method_name = "\"" .. conf.method .. "\"" .. "\n"

    local params_desc = "\"" .. conf.params_type_desc .. "\"" .. "\n"
    local params = ""
    local serialized = conf.serialized
    if conf.serialization_header_key then
        local serialization_header = core.request.header(ctx, conf.serialization_header_key)
        serialized = serialization_header == "true"
    end
    if serialized then
        params = core.request.get_body() .. "\n"
        local end_of_params = core.string.sub(params, -1)
        if not end_of_params == "\n" then
            params = params .. "\n"
        end
    else
        local body_data = core.request.get_body()
        if body_data then
            local lua_object = core.json.decode(body_data);
            for k, v in pairs(lua_object) do
                local pt = type(v)
                if pt == "nil" then
                    params = params .. "null" .. "\n"
                elseif pt == "string" then
                    params = params .. string_to_json_string(v) .. "\n"
                elseif pt == "number" then
                    params = params .. tostring(v) .. "\n"
                else
                    params = params .. core.json.encode(v) .. "\n"
                end
            end
        else
            ngx.say("Failed to get request body data.")
            return
        end
    end
    local attachments = "{}\n"

    local payload = #version + #service + #service_version + #method_name + #params_desc + #params + #attachments
    return {
        first_byte4,
        requestId,
        str_int32(payload),
        version,
        service,
        service_version,
        method_name,
        params_desc,
        params,
        attachments
    }
end

function _M.before_proxy(conf, ctx)
    local sock = ngx.socket.tcp()
    sock:settimeouts(6000, 6000, 6000)  -- one second timeout
    local ok, err = sock:connect(ctx.picked_server.host, ctx.picked_server.port)
    if not ok then
        ngx.say("failed to connect to upstream ", err)
        return
    end
    local request = get_dubbo_request(conf, ctx)
    local bytes, err = sock:send(request)
    if bytes > 0 then
        local header, err = sock:receiveany(16);
        if header then
            local header_info = parse_dubbo_header(header)
            if header_info and header_info.status == 20 then
                local readline = sock:receiveuntil("\n")
                local body_status, err, partial = readline()

                if body_status then
                    local response_status = core.string.sub(body_status, 1, 1)
                    if response_status == "2" or response_status == "5" then
                        return 200
                    elseif response_status == "1" or response_status == "4" then
                        local body, err, partial = readline()
                        return 200, body
                    end
                end
            end
        end
    end
    sock:close()
    return 500

end

return _M
