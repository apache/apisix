--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local helper = require("apisix.plugins.ext-plugin.helper")
local bit = require("bit")
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local ffi = require("ffi")
local ffi_str = ffi.string
local socket_tcp = ngx.socket.tcp
local str_byte = string.byte
local str_format = string.format


local lrucache = core.lrucache.new({
    type = "plugin",
    ttl = helper.get_conf_token_cache_time(),
})

local schema = {
    type = "object",
    properties = {},
}

local _M = {
    schema = schema,
}
local RPC_ERROR = 0
local RPC_PREPARE_CONF = 1
local RPC_HTTP_REQ_CALL = 2


local send
do
    local hdr_buf = ffi.new("unsigned char[4]")
    local buf = core.table.new(2, 0)
    local MAX_DATA_SIZE = lshift(1, 24) - 1

    function send(sock, ty, data)
        hdr_buf[0] = ty

        local len = #data

        core.log.info("sending rpc type: ", ty, " data length: ", len)

        if len > MAX_DATA_SIZE then
            return nil, str_format("the max length of data is %d but got %d", MAX_DATA_SIZE, len)
        end

        -- length is sent as big endian
        for i = 3, 1, -1 do
            hdr_buf[i] = band(len, 255)
            len = rshift(len, 8)
        end

        buf[1] = ffi_str(hdr_buf, 4)
        buf[2] = data
        return sock:send(buf)
    end
end
_M.send = send


local function receive(sock)
    local hdr, err = sock:receive(4)
    if not hdr then
        return nil, err
    end
    if #hdr ~= 4 then
        return nil, "header too short"
    end

    local ty = str_byte(hdr, 1)
    if ty == RPC_ERROR then
        return nil, "TODO: handler err"
    end

    local resp
    local hi, mi, li = str_byte(hdr, 2, 4)
    local len = 256 * (256 * hi + mi) + li

    core.log.info("receiving rpc type: ", ty, " data length: ", len)

    if len > 0 then
        resp, err = sock:receive(len)
        if not resp then
            return nil, err
        end
        if #resp ~= len then
            return nil, "data truncated"
        end
    end

    return ty, resp
end
_M.receive = receive


local rpc_call
local rpc_handlers = {
    nil,
    function (conf, ctx, sock)
        local req = "prepare"
        local ok, err = send(sock, RPC_PREPARE_CONF, req)
        if not ok then
            return nil, "failed to send RPC_PREPARE_CONF: " .. err
        end

        local ty, resp = receive(sock)
        if ty == nil then
            return nil, "failed to receive RPC_PREPARE_CONF: " .. resp
        end

        if ty ~= RPC_PREPARE_CONF then
            return nil, "failed to receive RPC_PREPARE_CONF: unexpected type " .. ty
        end

        core.log.warn(resp)
        return true
    end,
    function (conf, ctx, sock)
        local token, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, rpc_call,
                                                    RPC_PREPARE_CONF, conf, ctx)
        if not token then
            return nil, err
        end

        local req = "hello"
        local ok, err = send(sock, RPC_HTTP_REQ_CALL, req)
        if not ok then
            return nil, "failed to send RPC_HTTP_REQ_CALL: " .. err
        end

        local ty, resp = receive(sock)
        if ty == nil then
            return nil, "failed to receive RPC_HTTP_REQ_CALL: " .. resp
        end

        if ty ~= RPC_HTTP_REQ_CALL then
            return nil, "failed to receive RPC_HTTP_REQ_CALL: unexpected type " .. ty
        end

        core.log.warn(resp)
        return true
    end,
}


rpc_call = function (ty, conf, ctx)
    local path = helper.get_path()

    local sock = socket_tcp()
    sock:settimeouts(1000, 5000, 5000)
    local ok, err = sock:connect(path)
    if not ok then
        return nil, "failed to connect to the unix socket " .. path .. ": " .. err
    end

    local ok, err = rpc_handlers[ty + 1](conf, ctx, sock)
    if not ok then
        sock:close()
        return nil, err
    end

    local ok, err = sock:setkeepalive(180 * 1000, 32)
    if not ok then
        core.log.info("failed to setkeepalive: ", err)
    end
    return true
end


function _M.communicate(conf, ctx)
    local ok, err = rpc_call(RPC_HTTP_REQ_CALL, conf, ctx)
    if not ok then
        core.log.error(err)
        return 503
    end
end


return _M
