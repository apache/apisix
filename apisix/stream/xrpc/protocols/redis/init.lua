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
local commands = require("apisix.stream.xrpc.protocols.redis.commands")
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local ffi = require("ffi")
local ffi_str = ffi.string
local math_random = math.random
local OK = ngx.OK
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE
local sleep = ngx.sleep
local str_byte = string.byte
local str_fmt = string.format
local ipairs = ipairs
local tonumber = tonumber


-- redis protocol spec: https://redis.io/docs/reference/protocol-spec/
-- There is no plan to support inline command format
local _M = {}
local MAX_LINE_LEN = 128
local MAX_VALUE_LEN = 128
local PREFIX_ARR = str_byte("*")
local PREFIX_STR = str_byte("$")
local PREFIX_STA = str_byte("+")
local PREFIX_INT = str_byte(":")
local PREFIX_ERR = str_byte("-")


local lrucache = core.lrucache.new({
    type = "plugin",
})


local function create_matcher(conf)
    local matcher = {}
    --[[
        {"delay": 5, "key":"x", "commands":["GET", "MGET"]}
        {"delay": 5, "commands":["GET"]}
        => {
            get = {keys = {x = {delay = 5}, * = {delay = 5}}}
            mget = {keys = {x = {delay = 5}}}
        }
    ]]--
    for _, rule in ipairs(conf.faults) do
        for _, cmd in ipairs(rule.commands) do
            cmd = cmd:lower()
            local key = rule.key
            local kf = commands.cmd_to_key_finder[cmd]
            local key_matcher = matcher[cmd]
            if not key_matcher then
                key_matcher = {
                    keys = {}
                }
                matcher[cmd] = key_matcher
            end

            if not key or kf == false then
                key = "*"
            end

            if key_matcher.keys[key] then
                core.log.warn("override existent fault rule of cmd: ", cmd, ", key: ", key)
            end

            key_matcher.keys[key] = rule
        end
    end

    return matcher
end


local function get_matcher(conf, ctx)
    return core.lrucache.plugin_ctx(lrucache, ctx, nil, create_matcher, conf)
end


function _M.init_downstream(session)
    local conf = session.route.protocol.conf
    if conf and conf.faults then
        local matcher = get_matcher(conf, session.conn_ctx)
        session.matcher = matcher
    end

    session.req_id_seq = 0
    session.resp_id_seq = 0
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


local function read_req(session, sk)
    local narg, err = read_len(sk)
    if not narg then
        return nil, err
    end

    local cmd_line = core.tablepool.fetch("xrpc_redis_cmd_line", narg, 0)

    local n, err = read_len(sk)
    if not n then
        return nil, err
    end

    local p, err = sk:read(n + 2)
    if not p then
        return nil, err
    end

    local s = ffi_str(p, n)
    cmd_line[1] = s

    local key_finder
    local matcher = session.matcher
    if matcher then
        matcher = matcher[s:lower()]
        if matcher then
            key_finder = commands.cmd_to_key_finder[s] or commands.default_key_finder
        end
    end

    for i = 2, narg do
        local is_key = false
        if key_finder then
            is_key = key_finder(i, narg)
        end

        local n, err = read_len(sk)
        if not n then
            return nil, err
        end

        local s
        if not is_key and n > MAX_VALUE_LEN then
            -- avoid recording big value
            local p, err = sk:read(MAX_VALUE_LEN)
            if not p then
                return nil, err
            end

            local ok, err = sk:drain(n - MAX_VALUE_LEN + 2)
            if not ok then
                return nil, err
            end

            s = ffi_str(p, MAX_VALUE_LEN) .. "...(" .. n .. " bytes)"
        else
            local p, err = sk:read(n + 2)
            if not p then
                return nil, err
            end

            s = ffi_str(p, n)

            if is_key and matcher.keys[s] then
                matcher = matcher.keys[s]
                key_finder = nil
            end
        end

        cmd_line[i] = s
    end

    session.req_id_seq = session.req_id_seq + 1
    local ctx = sdk.get_req_ctx(session, session.req_id_seq)
    ctx.cmd_line = cmd_line
    ctx.cmd = ctx.cmd_line[1]

    local pipelined = sk:has_pending_data()

    if matcher then
        if matcher.keys then
            -- try to match any key of this command
            matcher = matcher.keys["*"]
        end

        if matcher then
            sleep(matcher.delay)
        end
    end

    return true, nil, pipelined
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
            return true
        end

        local ok, err = sk:drain(size + 2)
        if not ok then
            return nil, err
        end

        return true

    elseif prefix == PREFIX_STA then    -- char '+'
        -- print("status reply")
        return true

    elseif prefix == PREFIX_ARR then -- char '*'
        local narr = tonumber(ffi_str(line + 1, n - 1))

        -- print("multi-bulk reply: ", narr)
        if narr < 0 then
            return true
        end

        for i = 1, narr do
            local res, err = read_reply(sk)
            if res == nil then
                return nil, err
            end
        end
        return true

    elseif prefix == PREFIX_INT then    -- char ':'
        -- print("integer reply")
        return true

    elseif prefix == PREFIX_ERR then    -- char '-'
        -- print("error reply: ", n)
        return true

    else
        return nil, str_fmt("unknown prefix: \"%s\"", prefix)
    end
end


local function handle_reply(session, sk)
    local ok, err = read_reply(sk)
    if not ok then
        return nil, err
    end

    -- TODO: don't update resp_id_seq if the reply is subscribed msg
    session.resp_id_seq = session.resp_id_seq + 1
    local ctx = sdk.get_req_ctx(session, session.resp_id_seq)

    return ctx
end


function _M.from_downstream(session, downstream)
    local read_pipeline = false
    while true do
        local ok, err, pipelined = read_req(session, downstream)
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

    return OK
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


function _M.disconnect_upstream(session, upstream)
    sdk.disconnect_upstream(upstream, session.upstream_conf)
end


function _M.to_upstream(session, ctx, downstream, upstream)
    local ok, err = upstream:move(downstream)
    if not ok then
        core.log.error("failed to send to upstream: ", err)
        return DECLINED
    end

    return OK
end


function _M.from_upstream(session, downstream, upstream)
    local ctx, err = handle_reply(session, upstream)
    if ctx == nil then
        core.log.error("failed to handle upstream: ", err)
        return DECLINED
    end

    local ok, err = downstream:move(upstream)
    if not ok then
        core.log.error("failed to handle upstream: ", err)
        return DECLINED
    end

    return DONE, ctx
end


function _M.log(session, ctx)
    core.tablepool.release("xrpc_redis_cmd_line", ctx.cmd_line)
    ctx.cmd_line = nil
end


return _M
