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
local ffi = require("ffi")
local ffi_str = ffi.string
local math_random = math.random
local OK = ngx.OK
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE
local str_byte = string.byte
local str_fmt = string.format
local tonumber = tonumber


-- redis protocol spec: https://redis.io/docs/reference/protocol-spec/
-- There is no plan to support inline command format
local _M = {}
local MAX_LINE_LEN = 128
local PREFIX_ARR = str_byte("*")
local PREFIX_STR = str_byte("$")
local PREFIX_STA = str_byte("+")
local PREFIX_INT = str_byte(":")
local PREFIX_ERR = str_byte("-")


function _M.init_downstream(session)
    return xrpc_socket.downstream.socket()
end


local function read_line(sk)
    local p, err, len = sk:read_line(MAX_LINE_LEN)
    if not p then
        return nil, err
    end

    if len < 2 then
        return nil, "line too short"
    end

    return p, nil, len
end


local function read_len(sk)
    local p, err, len = read_line(sk)
    if not p then
        return nil, err
    end

    local s = ffi_str(p + 1, len - 1)
    local n = tonumber(s)
    if not n then
        return nil, str_fmt("invalid len string: \"%s\"", s)
    end
    return n
end


local function read_req(sk)
    local narg, err = read_len(sk)
    if not narg then
        return nil, err
    end

    local ctx = {
        cmd_line = core.table.new(narg, 0)
    }

    for i = 1, narg do
        local n, err = read_len(sk)
        if not n then
            return nil, err
        end

        local p, err = sk:read(n + 2)
        if not p then
            return nil, err
        end

        local s = ffi_str(p, n)
        ctx.cmd_line[i] = s
    end

    ctx.cmd = ctx.cmd_line[1]
    return ctx
end


local function read_reply(sk)
    local line, err, n = read_line(sk)
    if not line then
        return nil, err
    end

    local prefix = line[0]

    if prefix == PREFIX_STR then    -- char '$'
        -- print("bulk reply")

        local size = tonumber(ffi_str(line + 1, n - 1))
        if size < 0 then
            -- return null
            return true
        end

        local ok, err = sk:drain(size + 2)
        if not ok then
            return nil, err
        end

        return true

    elseif prefix == PREFIX_STA then    -- char '+'
        -- print("status reply")
        -- return sub(line, 2)
        return true

    elseif prefix == PREFIX_ARR then -- char '*'
        local narr = tonumber(ffi_str(line + 1, n - 1))

        -- print("multi-bulk reply: ", narr)
        if narr < 0 then
            -- return null
            return true
        end

        local vals = core.table.new(n, 0)
        local nvals = 0
        for i = 1, narr do
            local res, err = read_reply(sk)
            if res then
                nvals = nvals + 1
                vals[nvals] = res

            elseif res == nil then
                return nil, err

            else
                -- be a valid redis error value
                nvals = nvals + 1
                vals[nvals] = {false, err}
            end
        end

        return vals

    elseif prefix == PREFIX_INT then    -- char ':'
        -- print("integer reply")
        -- return tonumber(str_sub(line, 2))
        return true

    elseif prefix == PREFIX_ERR then    -- char '-'
        -- print("error reply: ", n)
        -- return false, str_sub(line, 2)
        return true

    else
        return nil, str_fmt("unknown prefix: \"%s\"", prefix)
    end
end


function _M.from_downstream(session, downstream)
    local ctx, err = read_req(downstream)
    if not ctx then
        if err ~= "timeout" and err ~= "closed" then
            core.log.error("failed to read request: ", err)
        end
        return DECLINED
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

    return OK, sk
end


function _M.to_upstream(session, ctx, downstream, upstream)
    local ok, err = upstream:move(downstream)
    if not ok then
        core.log.error("failed to send to upstream: ", err)
        return DECLINED
    end

    local p, err = read_reply(upstream)
    if p == nil then
        core.log.error("failed to handle upstream: ", err)
        return DECLINED
    end

    local ok, err = downstream:move(upstream)
    if not ok then
        core.log.error("failed to handle upstream: ", err)
        return DECLINED
    end

    return DONE
end


function _M.log(session, ctx)
    -- TODO
end


return _M
