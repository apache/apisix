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
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local bit = require("bit")
local lshift = bit.lshift
local ffi = require("ffi")
local ffi_str = ffi.string
local math_random = math.random
local OK = ngx.OK
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE
local str_byte = string.byte


-- pingpong protocol is designed to use in the test of xRPC.
-- It contains two part: a fixed-length header & a body.
-- Header format:
-- "pp" (magic number) + 1 bytes req type + 2 bytes stream id + 1 reserved bytes
-- + 4 bytes body length
local _M = {}
local HDR_LEN = 10
local TYPE_HEARTBEAT = 1
local TYPE_UNARY = 2


function _M.init_worker()
    core.log.info("call pingpong's init_worker")
end


function _M.init_downstream(session)
    -- create the downstream
    local sk = xrpc_socket.downstream.socket()
    sk:settimeout(10) -- the short timeout is just for test
    return sk
end


local function read_data(sk, len, body)
    local f = body and sk.drain or sk.read
    local p, err = f(sk, len)
    if not p then
        if err == "closed" then
            core.log.info("failed to read: ", err)
        else
            core.log.error("failed to read: ", err)
        end
        return nil
    end

    return p
end


local function to_int32(p, idx)
    return lshift(p[idx], 24) + lshift(p[idx + 1], 16) + lshift(p[idx + 2], 8) + p[idx + 3]
end


function _M.from_downstream(session, downstream)
    -- read a request from downstream
    -- return status and the new ctx
    core.log.info("call pingpong's from_downstream")

    local p = read_data(downstream, HDR_LEN, false)
    if p == nil then
        return DECLINED
    end

    local p_b = str_byte("p")
    if p[0] ~= p_b or p[1] ~= p_b then
        core.log.error("invalid magic number: ", ffi_str(p, 2))
        return DECLINED
    end

    local typ = p[2]
    if typ == TYPE_HEARTBEAT then
        core.log.info("send heartbeat")

        -- need to reset read buf as we won't forward it
        downstream:reset_read_buf()
        downstream:send(ffi_str(p, HDR_LEN))
        return DONE
    end

    local body_len = to_int32(p, 6)
    core.log.info("read body len: ", body_len)

    local p = read_data(downstream, body_len, true)
    if p == nil then
        return DECLINED
    end

    return OK, {
        is_unary = typ == TYPE_UNARY,
        len = HDR_LEN + body_len
    }
end


function _M.connect_upstream(session, ctx)
    -- connect the upstream with upstream_conf
    -- also do some handshake jobs
    -- return status and the new upstream
    core.log.info("call pingpong's connect_upstream")

    local conf = session.upstream_conf
    local nodes = conf.nodes
    if #nodes == 0 then
        core.log.error("failed to connect: no nodes")
        return DECLINED
    end
    local node = nodes[math_random(#nodes)]
    local sk = xrpc_socket.upstream.socket()
    sk:settimeout(10) -- the short timeout is just for test
    local ok, err = sk:connect(node.host, node.port)
    if not ok then
        core.log.error("failed to connect: ", err)
        return DECLINED
    end

    if conf.scheme == "tls" then
        local ok, err = sk:sslhandshake(nil, node.host)
        if not ok then
            core.log.error("failed to handshake: ", err)
            return DECLINED
        end
    end

    return OK, sk
end


function _M.to_upstream(session, ctx, downstream, upstream)
    -- send the request read from downstream to the upstream
    -- return whether the request is sent
    core.log.info("call pingpong's to_upstream")

    local ok, err = upstream:move(downstream)
    if not ok then
        core.log.error("failed to send to upstream: ", err)
        return DECLINED
    end

    if ctx.is_unary then
        local p = read_data(upstream, ctx.len, false)
        if p == nil then
            return DECLINED
        end

        local ok, err = downstream:move(upstream)
        if not ok then
            core.log.error("failed to handle upstream: ", err)
            return DECLINED
        end

        return DONE
    end

    return OK
end


function _M.log(session, ctx)
    core.log.info("call pingpong's log")
end


return _M
