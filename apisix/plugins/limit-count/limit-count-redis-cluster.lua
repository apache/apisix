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

local redis_cluster = require("apisix.utils.rediscluster")
local core = require("apisix.core")
local setmetatable = setmetatable
local tostring = tostring
local ngx_var = ngx.var

local _M = {version = 0.2}


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
    local req_id = ARGV[5]

    local window_start = now - window

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
        local member = req_id .. ':' .. i
        redis.call('ZADD', KEYS[1], now, member)
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


local script_approximate_sliding = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 1, "cost must be at least 1")

    local now = tonumber(ARGV[1])
    local window = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    local cost = tonumber(ARGV[4])

    -- Calculate window IDs
    local window_id = math.floor(now / window)
    local prev_window_id = window_id - 1

    -- Get counts from current and previous windows
    local curr_key = KEYS[1] .. ':' .. window_id
    local prev_key = KEYS[1] .. ':' .. prev_window_id

    local curr_count = tonumber(redis.call('GET', curr_key) or 0)
    local prev_count = tonumber(redis.call('GET', prev_key) or 0)

    -- Calculate elapsed time in current window
    local elapsed = now % window
    local rate = elapsed / window

    -- Approximate sliding window count
    local approximate_count = prev_count * (1 - rate) + curr_count
    local remaining = limit - (approximate_count + cost)
    local reset = window - elapsed

    if reset < 0 or reset > window then
        reset = 0
    end

    if remaining < 0 then
        return {-1, reset}
    end

    local new_count = redis.call('INCRBY', curr_key, cost)
    if new_count == cost then
        redis.call('PEXPIRE', curr_key, window * 2)
    end

    return {remaining, reset}
]=])


function _M.new(plugin_name, limit, window, window_type, conf)
    local red_cli, err = redis_cluster.new(conf, "plugin-limit-count-redis-cluster-slot-lock")
    if not red_cli then
        return nil, err
    end

    local self = {
        limit = limit,
        window = window,
        window_type = window_type or "fixed",
        conf = conf,
        plugin_name = plugin_name,
        red_cli = red_cli,
    }

    return setmetatable(self, mt)
end


function _M.incoming(self, key, cost)
    local red = self.red_cli
    key = self.plugin_name .. tostring(key)

    local ttl = 0
    local limit = self.limit
    local c = cost or 1
    local res

    if self.window_type == "sliding" then
        local now = ngx.now() * 1000
        local window = self.window * 1000
        local req_id = ngx_var.request_id

        res, err = red:eval(script_sliding, 1, key, now, window, limit, c, req_id)
    elseif self.window_type == "approximate_sliding" then
        local now = ngx.now() * 1000
        local window = self.window * 1000

        res, err = red:eval(script_approximate_sliding, 1, key, now, window, limit, c)
    else
        local window = self.window

        res, err = red:eval(script_fixed, 1, key, limit, window, c)
    end

    if err then
        return nil, err, ttl
    end

    local remaining = res[1]
    ttl = res[2]

    if remaining < 0 then
        return nil, "rejected", ttl
    end
    return 0, remaining, ttl
end


return _M
