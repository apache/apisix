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

local assert            = assert
local math              = require "math"
local floor             = math.floor
local ngx               = ngx
local ngx_time          = ngx.time
local uuid              = require("resty.jit-uuid")

local _M = {version = 0.3}
local redis_incoming_script = [[
    local key = KEYS[1]
    local limit = tonumber(ARGV[1])
    local ttl = tonumber(ARGV[2])
    local now = tonumber(ARGV[3])
    local req_id = ARGV[4]

    redis.call('ZREMRANGEBYSCORE', key, 0, now)

    local count = redis.call('ZCARD', key)
    if count >= limit then
        return {0, count}
    end

    redis.call('ZADD', key, now + ttl, req_id)
    redis.call('EXPIRE', key, ttl)
    return {1, count + 1}
]]


function _M.incoming(self, red, key, commit)
    local max = self.max
    self.committed = false
    local raw_key = key
    key = "limit_conn" .. ":" .. key

    local conn
    if commit then
        local req_id = ngx.ctx.request_id or uuid.generate_v4()
        if not ngx.ctx.limit_conn_req_ids then
            ngx.ctx.limit_conn_req_ids = {}
        end
        ngx.ctx.limit_conn_req_ids[raw_key] = req_id

        local now = ngx_time()
        local res, err = red:eval(redis_incoming_script, 1, key,
                                    max + self.burst, self.conf.key_ttl, now, req_id)
        if not res then
            return nil, err
        end

        local allowed = res[1]
        conn = res[2]

        if allowed == 0 then
            return nil, "rejected"
        end

        self.committed = true

    else
        red:zremrangebyscore(key, 0, ngx_time())
        local count, err = red:zcard(key)
        if err then return nil, err end
        conn = (count or 0) + 1
    end

    if conn > max then
        -- make the excessive connections wait
        return self.unit_delay * floor((conn - 1) / max), conn
    end

    -- we return a 0 delay by default
    return 0, conn
end


function _M.leaving(self, red, key, req_latency, req_id)
    assert(key)
    key = "limit_conn" .. ":" .. key

    local conn, err
    if req_id then
        local res, err = red:zrem(key, req_id)
        if not res then
            return nil, err
        end
    end
    conn, err = red:zcard(key)

    if not conn then
        return nil, err
    end

    if req_latency then
        local unit_delay = self.unit_delay
        self.unit_delay = (req_latency + unit_delay) / 2
    end

    return conn
end


return _M
