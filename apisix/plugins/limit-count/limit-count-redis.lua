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
local redis     = require("apisix.utils.redis")
local core = require("apisix.core")
local assert = assert
local setmetatable = setmetatable
local tostring = tostring


local _M = {version = 0.4}


local mt = {
    __index = _M
}


local script_fixed = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 1, "cost must be at least 1")
    local ttl = redis.call('ttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1] - ARGV[3], 'EX', ARGV[2])
        return {ARGV[1] - ARGV[3], ARGV[2]}
    end
    return {redis.call('incrby', KEYS[1], 0 - ARGV[3]), ttl}
]=])


local script_sliding = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 1, "cost must be at least 1")

    local now = tonumber(ARGV[1])
    local window = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    local cost = tonumber(ARGV[4])

    local window_start = now - window

    -- remove events outside of the window
    redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, window_start)

    local current = redis.call('ZCARD', KEYS[1])

    if current + cost > limit then
        local earliest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
        local reset = 0
        if #earliest == 2 then
            reset = earliest[2] + window - now
            if reset < 0 then
                reset = 0
            end
        end
        return {-1, reset}
    end

    for i = 1, cost do
        redis.call('ZADD', KEYS[1], now, now .. ':' .. i)
    end

    redis.call('PEXPIRE', KEYS[1], window)

    local remaining = limit - (current + cost)

    local earliest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
    local reset = 0
    if #earliest == 2 then
        reset = earliest[2] + window - now
        if reset < 0 then
            reset = 0
        end
    end

    return {remaining, reset}
]=])


function _M.new(plugin_name, limit, window, window_type, conf)
    assert(limit > 0 and window > 0)

    local self = {
        limit = limit,
        window = window,
        window_type = window_type or "fixed",
        conf = conf,
        plugin_name = plugin_name,
    }
    return setmetatable(self, mt)
end

function _M.incoming(self, key, cost)
    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err, 0
    end

    key = self.plugin_name .. tostring(key)

    local ttl = 0
    local limit = self.limit
    local c = cost or 1
    local res

    if self.window_type == "sliding" then
        local now = ngx.now() * 1000
        local window = self.window * 1000

        res, err = red:eval(script_sliding, 1, key, now, window, limit, c)
    else
        local window = self.window
        res, err = red:eval(script_fixed, 1, key, limit, window, c)
    end

    if err then
        return nil, err, ttl
    end

    local remaining = res[1]
    ttl = res[2]

    local ok, err2 = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err2, ttl
    end

    if remaining < 0 then
        return nil, "rejected", ttl
    end

    return 0, remaining, ttl
end


return _M
