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
