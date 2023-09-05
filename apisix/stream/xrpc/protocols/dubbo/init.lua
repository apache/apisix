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
local sdk = require("apisix.stream.xrpc.sdk")
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local math_random = math.random
local ngx = ngx
local OK = ngx.OK
local str_format = string.format
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE
local bit = require("bit")
local ffi = require("ffi")
local ffi_str = ffi.string


-- dubbo protocol spec: https://cn.dubbo.apache.org/zh-cn/overview/reference/protocols/tcp/
local header_len = 16
local _M = {}


function _M.init_downstream(session)
    session.req_id_seq = 0
    session.resp_id_seq = 0
    session.cmd_labels = { session.route.id, "" }
    return xrpc_socket.downstream.socket()
end


local function parse_dubbo_header(header)
    for i = 1, header_len do
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


local function read_data(sk, is_req)
    local header_data, err = sk:read(header_len)
    if not header_data then
        return nil, err, false
    end

    local header_str = ffi_str(header_data, header_len)
    local header_info = parse_dubbo_header(header_str)
    if not header_info then
        return nil, "header insufficient", false
    end

    local is_valid_magic_number = header_info.magic_number == "dabb"
    if not is_valid_magic_number then
        return nil, str_format("unknown magic number: \"%s\"", header_info.magic_number), false
    end

    local body_data, err = sk:read(header_info.data_length)
    if not body_data then
        core.log.error("failed to read dubbo request body")
        return nil, err, false
    end

    local ctx = ngx.ctx
    ctx.dubbo_serialization_id = bit.band(header_info.message_flag, 0x1F)

    if is_req then
        ctx.dubbo_req_body_data = body_data
    else
        ctx.dubbo_rsp_body_data = body_data
    end

    return true, nil, false
end


local function read_req(sk)
    return read_data(sk, true)
end


local function read_reply(sk)
    return read_data(sk, false)
end


local function handle_reply(session, sk)
    local ok, err = read_reply(sk)
    if not ok then
        return nil, err
    end

    local ctx = sdk.get_req_ctx(session, 10)

    return ctx
end


function _M.from_downstream(session, downstream)
    local read_pipeline = false
    session.req_id_seq = session.req_id_seq + 1
    local ctx = sdk.get_req_ctx(session, session.req_id_seq)
    session._downstream_ctx = ctx
    while true do
        local ok, err, pipelined = read_req(downstream)
        if not ok then
            if err ~= "timeout" and err ~= "closed" then
                core.log.error("failed to read request: ", err)
            end

            if read_pipeline and err == "timeout" then
                break
            end

            return DECLINED
        end

        if not pipelined then
            break
        end

        if not read_pipeline then
            read_pipeline = true
            -- set minimal read timeout to read pipelined data
            downstream:settimeouts(0, 0, 1)
        end
    end

    if read_pipeline then
        -- set timeout back
        downstream:settimeouts(0, 0, 0)
    end

    return OK, ctx
end


function _M.connect_upstream(session, ctx)
    local conf = session.upstream_conf
    local nodes = conf.nodes
    if #nodes == 0 then
        core.log.error("failed to connect: no nodes")
        return DECLINED
    end

    local node = nodes[math_random(#nodes)]
    local sk = sdk.connect_upstream(node, conf)
    if not sk then
        return DECLINED
    end

    core.log.debug("dubbo_connect_upstream end")

    return OK, sk
end

function _M.disconnect_upstream(session, upstream)
    sdk.disconnect_upstream(upstream, session.upstream_conf)
end


function _M.to_upstream(session, ctx, downstream, upstream)
    local ok, _ = upstream:move(downstream)
    if not ok then
        return DECLINED
    end

    return OK
end


function _M.from_upstream(session, downstream, upstream)
    local ctx,err = handle_reply(session, upstream)
    if err then
        return DECLINED
    end

    local ok, _ = downstream:move(upstream)
    if not ok then
        return DECLINED
    end

    return DONE, ctx
end


function _M.log(_, _)
end


return _M
