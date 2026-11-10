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
local ngx_null  = ngx.null
local tonumber  = tonumber
local core      = require("apisix.core")
local to_hex    = require("resty.string").to_hex

local _M = {}


local incr_script = core.string.compress_script([=[
    local ttl = redis.call('pttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1], 'EX', ARGV[2])
        return tonumber(ARGV[1])
    end
    return redis.call('incrby', KEYS[1], ARGV[1])
]=])
local incr_script_sha = to_hex(ngx.sha1_bin(incr_script))


-- Decide accept/reject and increment (only on accept) in one atomic step, so
-- concurrent requests can't all pass the check before an increment lands.
-- KEYS[1] is the current window counter; the previous window's count comes via
-- ARGV because it is frozen (in the past, never written concurrently) and
-- redis-cluster only allows single-key EVAL. Returns {accepted, count, last}:
-- count is the post-incr value on accept, else the current count; last is the
-- previous window count, capped at the limit.
local check_incr_script = core.string.compress_script([=[
    local cost = tonumber(ARGV[1])
    local limit = tonumber(ARGV[2])
    local window_size = tonumber(ARGV[3])
    local remaining_time = tonumber(ARGV[4])
    local expiry = ARGV[5]
    local last = tonumber(ARGV[6])
    if last > limit then
        last = limit
    end

    local cur_ttl = redis.call('pttl', KEYS[1])
    local cur = 0
    if cur_ttl >= 0 then
        cur = tonumber(redis.call('get', KEYS[1]) or 0)
    end

    local estimated = last / window_size * remaining_time + cur
    if cur >= limit or estimated >= limit then
        return {0, cur, last}
    end

    local new
    if cur_ttl < 0 then
        redis.call('set', KEYS[1], cost, 'EX', expiry)
        new = cost
    else
        new = redis.call('incrby', KEYS[1], cost)
    end
    return {1, new, last}
]=])
local check_incr_script_sha = to_hex(ngx.sha1_bin(check_incr_script))


-- TODO: keepalive or close
function _M.incr(self, key, delta, expiry, red)
    --                                          nk  key1  argv1  argv2
    local new_value, err
    new_value, err = red:evalsha(incr_script_sha, 1, key, delta, expiry)
    if err and core.string.has_prefix(err, "NOSCRIPT") then
        core.log.warn("redis evalsha failed: ", err, ". Falling back to eval")
        new_value, err = red:eval(incr_script, 1, key, delta, expiry)
    end
    if err then
        return nil, err
    end

    if not new_value then
        return nil, "malformed redis response while calling incr"
    end

    return new_value
end


function _M.check_and_incr(self, current_key, last_key, cost, limit,
                           window_size, remaining_time, expiry, red)
    -- previous window is frozen, so a single-key GET is safe and keeps the
    -- atomic EVAL to one key, which redis-cluster requires
    local last, err = red:get(last_key)
    if err then
        return nil, err
    end
    if not last or last == ngx_null then
        last = 0
    end

    local res
    res, err = red:evalsha(check_incr_script_sha, 1, current_key,
                           cost, limit, window_size, remaining_time, expiry, last)
    if err and core.string.has_prefix(err, "NOSCRIPT") then
        core.log.warn("redis evalsha failed: ", err, ". Falling back to eval")
        res, err = red:eval(check_incr_script, 1, current_key,
                            cost, limit, window_size, remaining_time, expiry, last)
    end
    if err then
        return nil, err
    end

    if not res then
        return nil, "malformed redis response while calling check_and_incr"
    end

    return res
end


-- TODO: keepalive or close
function _M.get(self, key, red)
    local value, err = red:get(key)
    if not value or value == ngx_null then
        return nil, err
    end

    value = tonumber(value)
    if not value then -- maybe warn log?
        return nil, "redis counter is not a number the value could have been modified"
    end

    return value, nil
end

return _M
