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
local math              = require "math"
local abs               = math.abs
local max               = math.max
local ngx_now           = ngx.now
local ngx_null          = ngx.null
local tonumber          = tonumber
local core              = require("apisix.core")


local _M = {version = 0.1}


-- Redis Lua script that reads, decays and persists the leaky-bucket state in a
-- single atomic step. With separate GET/GET/SET/SET commands, concurrent
-- requests can each read the same stale excess value, all conclude they are
-- within limits, and all get admitted, exceeding the configured rate.
--
-- KEYS[1] = excess_key, KEYS[2] = last_key
-- Both keys must share the same hash tag so they land on the same Redis
-- Cluster slot (Redis Cluster rejects EVAL with keys on different slots).
-- ARGV[1] = rate (req/s * 1000), ARGV[2] = burst (* 1000), ARGV[3] = now (ms),
-- ARGV[4] = ttl (seconds)
-- Returns {excess, 0}  on allow  (excess already stored)
--         {-1, excess} on reject (nothing stored)
local redis_commit_script = core.string.compress_script([=[
    local excess_key = KEYS[1]
    local last_key   = KEYS[2]
    local rate       = tonumber(ARGV[1])
    local burst      = tonumber(ARGV[2])
    local now        = tonumber(ARGV[3])
    local ttl        = tonumber(ARGV[4])

    local excess_raw = redis.call('get', excess_key)
    local last_raw   = redis.call('get', last_key)

    local excess
    if excess_raw and last_raw then
        -- keys exist: apply leaky-bucket decay then add one request-unit (1000)
        local elapsed = now - tonumber(last_raw)
        excess = math.max(tonumber(excess_raw) - rate * math.abs(elapsed) / 1000 + 1000, 0)

        if excess > burst then
            return {-1, excess}
        end
    else
        -- no prior state: mirror the original behaviour, which skips the
        -- leaky-bucket formula and starts with excess = 0 so the very first
        -- request is always admitted
        excess = 0
    end

    redis.call('set', excess_key, excess, 'EX', ttl)
    redis.call('set', last_key, now, 'EX', ttl)
    return {excess, 0}
]=])


-- the "commit" argument controls whether should we record the event in shm.
function _M.incoming(self, red, key, commit)
    local rate = self.rate
    local now = ngx_now() * 1000

    -- Use a hash tag so that excess_key and last_key always land on the same
    -- Redis Cluster slot. Redis Cluster hashes only the substring inside the
    -- first "{...}" pair, so both keys share slot(limit_req:<key>) regardless
    -- of their suffixes.
    local base_key = "limit_req" .. ":" .. key
    local excess_key = "{" .. base_key .. "}excess"
    local last_key = "{" .. base_key .. "}last"

    if not commit then
        -- read-only path: two separate GETs are fine here because nothing is
        -- written back, so a stale read only affects this advisory check
        local excess, err = red:get(excess_key)
        if err then
            return nil, err
        end
        local last, err2 = red:get(last_key)
        if err2 then
            return nil, err2
        end

        local excess_val
        if excess ~= ngx_null and last ~= ngx_null then
            excess_val = tonumber(excess)
            local last_val = tonumber(last)
            local elapsed = now - last_val
            excess_val = max(excess_val - rate * abs(elapsed) / 1000 + 1000, 0)

            if excess_val > self.burst then
                return nil, "rejected"
            end
        else
            excess_val = 0
        end

        return excess_val / rate, excess_val / 1000
    end

    -- commit path: run the read-compute-write cycle atomically in Redis so
    -- that concurrent requests cannot be admitted based on the same stale
    -- state
    local ttl = math.ceil(self.burst / self.rate) + 1

    local res, err = red:eval(redis_commit_script, 2,
                              excess_key, last_key,
                              rate, self.burst, now, ttl)
    if not res then
        return nil, err
    end

    local excess = res[1]
    if excess == -1 then
        -- the script signals rejection; res[2] holds the actual excess value
        return nil, "rejected"
    end

    -- return the delay in seconds, as well as excess
    return excess / rate, excess / 1000
end


return _M
