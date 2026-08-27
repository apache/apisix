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

local ngx = require("ngx")
local redis = require "resty.redis"

local ipairs = ipairs
local tonumber = tonumber

local _M = {}

-- 6479 is the sentinel master used by the redis-sentinel policies; leftover
-- counters there survive CI re-runs if it is not flushed
local DEFAULT_PORTS = {6379, 6479, 5000, 5001, 5002, 5003, 5004, 5005, 5006}
local DEFAULT_HOST = "127.0.0.1"

local function log_warn(...)
    if ngx then
        ngx.log(ngx.WARN, ...)
    end
end

local function add_port(target, visited, port)
    port = tonumber(port)
    if port and not visited[port] then
        visited[port] = true
        target[#target + 1] = port
    end
end

local function auth_if_needed(red, opts)
    opts = opts or {}
    local username = opts.username
    local password = opts.password
    if not password or password == "" then
        return true
    end

    local ok, err
    if username and username ~= "" then
        ok, err = red:auth(username, password)
    else
        ok, err = red:auth(password)
    end

    if ok then
        return true
    end

    if err and (err:find("no password is set", 1, true)
        or err:find("without any password configured", 1, true)) then
        return true
    end

    log_warn("failed to auth redis: ", err)
    return nil, err
end

local function release(red, host, port, opts)
    local keepalive_pool = opts.keepalive_pool
    if keepalive_pool == nil then
        keepalive_pool = 0
    end
    if keepalive_pool == 0 then
        local ok_close, close_err = red:close()
        if not ok_close then
            log_warn("failed to close redis connection ", host, ":", port, ": ", close_err)
        end
    else
        local keepalive_timeout = opts.keepalive_timeout or 10000
        local ok_keepalive, keepalive_err = red:set_keepalive(keepalive_timeout, keepalive_pool)
        if not ok_keepalive then
            log_warn("failed to set keepalive for redis ", host, ":", port, ": ", keepalive_err)
        end
    end
end

local function connect(host, port, opts)
    local red = redis:new()
    local connect_timeout = opts.connect_timeout or 1000
    local send_timeout = opts.send_timeout or connect_timeout
    local read_timeout = opts.read_timeout or connect_timeout
    red:set_timeouts(connect_timeout, send_timeout, read_timeout)

    local ok, err = red:connect(host, port)
    if not ok then
        log_warn("failed to connect to redis ", host, ":", port, ": ", err)
        return nil, err
    end

    local ok_auth, auth_err = auth_if_needed(red, opts)
    if not ok_auth then
        release(red, host, port, {})
        return nil, auth_err
    end

    if opts.database then
        local ok_select, select_err = red:select(opts.database)
        if not ok_select then
            log_warn("failed to select redis db ", opts.database, ": ", select_err)
            release(red, host, port, {})
            return nil, select_err
        end
    end

    return red
end

local function flush_single(host, port, opts)
    local red, err = connect(host, port, opts)
    if not red then
        return nil, err
    end

    local _, flush_err = red:flushall()
    if flush_err then
        log_warn("failed to flush redis ", host, ":", port, ": ", flush_err)
    end

    release(red, host, port, opts)

    return true
end

function _M.flush_all(opts)
    opts = opts or {}
    local host = opts.host or DEFAULT_HOST

    local visited = {}
    local ports = {}

    local source_ports = opts.ports or DEFAULT_PORTS
    for _, port in ipairs(source_ports) do
        add_port(ports, visited, port)
    end

    add_port(ports, visited, os.getenv("TEST_NGINX_REDIS_PORT"))

    if opts.extra_ports then
        for _, port in ipairs(opts.extra_ports) do
            add_port(ports, visited, port)
        end
    end

    for _, port in ipairs(ports) do
        flush_single(host, port, opts)
    end
end

function _M.flush_port(host, port, opts)
    if type(host) == "table" then
        opts = host
        host = opts.host or DEFAULT_HOST
        port = opts.port
    end

    opts = opts or {}
    host = host or opts.host or DEFAULT_HOST
    port = port or opts.port
    if not port then
        return nil, "port is required"
    end

    return flush_single(host, port, opts)
end

-- Rate limit counters are committed from a log phase timer, so a request fired
-- right after the previous one can still be judged against a budget that looks
-- unspent. Snapshot the counters with sum_counters() before a request and wait
-- for the total to grow with wait_counters_above() afterwards, rather than
-- sleeping a fixed amount: a wait long enough to cover a busy machine would roll
-- over the short time windows some of these tests configure.
function _M.sum_counters(pattern, opts)
    opts = opts or {}
    local host = opts.host or DEFAULT_HOST
    local port = opts.port or 6379

    local red, err = connect(host, port, opts)
    if not red then
        return nil, err
    end

    local keys, keys_err = red:keys(pattern)
    if not keys then
        release(red, host, port, opts)
        return nil, keys_err
    end

    local total = 0
    for _, key in ipairs(keys) do
        -- a key that expired between keys() and get() reads back as ngx.null,
        -- which is not an error; keep the two apart so a failed read cannot be
        -- mistaken for a counter of zero
        local value, get_err = red:get(key)
        if not value then
            release(red, host, port, opts)
            return nil, get_err
        end
        total = total + (tonumber(value) or 0)
    end

    release(red, host, port, opts)

    return total
end

function _M.wait_counters_above(pattern, previous, opts)
    local last_err
    for _ = 1, 100 do
        local total, err = _M.sum_counters(pattern, opts)
        if total and total > previous then
            return true
        end
        last_err = err
        ngx.sleep(0.01)
    end

    return nil, "counters matching " .. pattern .. " stayed at " .. previous ..
                (last_err and (", last error: " .. last_err) or "")
end

_M.default_ports = DEFAULT_PORTS

return _M
