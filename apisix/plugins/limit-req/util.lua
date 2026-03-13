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
local ngx_now           = ngx.now
local tonumber          = tonumber
local core              = require("apisix.core")


local _M = {version = 0.1}


local redis_incoming_script = core.string.compress_script([=[
  local state_key  = KEYS[1]             -- state_key (hash), fields: "excess", "last"
  local rate       = tonumber(ARGV[1])   -- req/s
  local now        = tonumber(ARGV[2])   -- ms
  local burst      = tonumber(ARGV[3])   -- req/s
  local commit     = tonumber(ARGV[4])   -- 1/0

  local vals = redis.call("HMGET", state_key, "excess", "last")
  local prev_excess = tonumber(vals[1] or "0")
  local prev_last   = tonumber(vals[2] or "0")

  local new_excess
  if prev_last > 0 then
    local elapsed = math.abs(now - prev_last)
    new_excess = math.max(prev_excess - rate * (elapsed) / 1000 + 1000, 0)
  else
    new_excess = 0
  end

  if new_excess > burst then
    return {0, new_excess}
  end

  if commit == 1 then
    redis.call("HMSET", state_key, "excess", new_excess, "last", now)
    local ttl = math.ceil(burst / rate) + 1
    redis.call("EXPIRE", state_key, ttl)
  end

  return {1, new_excess}
]=])

local redis_incoming_script_sha


local function generate_redis_sha1(red)
    local sha1, err = red:script("LOAD", redis_incoming_script)
    if not sha1 then
        return nil, err
    end
    return sha1
end


-- the "commit" argument controls whether should we record the event in shm.
function _M.incoming(self, red, key, commit)
    local rate = self.rate
    local now = ngx_now() * 1000

    local state_key = "limit_req:{" .. key .. "}:state"

    local commit_flag = commit and "1" or "0"

    local res, err

    if self.use_evalsha then
        if not redis_incoming_script_sha then
            redis_incoming_script_sha, err = generate_redis_sha1(red)
            if not redis_incoming_script_sha then
                core.log.error("failed to generate redis sha1: ", err)
                return nil, err
            end
        end
        -- Try EVALSHA first (fast path).
        res, err = red:evalsha(redis_incoming_script_sha, 1, state_key,
                              rate, now, self.burst, commit_flag)

        -- If the script isn't cached on this Redis node, fall back to EVAL.
        if err and core.string.has_prefix(err, "NOSCRIPT") then
            core.log.warn("redis evalsha failed: ", err, ". Falling back to eval...")
            redis_incoming_script_sha = nil
            res, err = red:eval(redis_incoming_script, 1, state_key,
                                rate, now, self.burst, commit_flag)
        end
    else
        -- rediscluster: prefer reliability (scripts are cached per node)
        res, err = red:eval(redis_incoming_script, 1, state_key,
                            rate, now, self.burst, commit_flag)
    end

    if not res then
        return nil, err
    end

    local allowed = tonumber(res[1]) == 1
    local excess  = tonumber(res[2]) or 0

    if not allowed then
        return nil, "rejected"
    end

    -- return the delay in seconds, as well as excess
    return excess / rate, excess / 1000
end


return _M
