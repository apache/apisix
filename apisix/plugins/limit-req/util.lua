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


local _M = {version = 0.1}


function _M.incoming(self, red, key, commit)
    local rate = self.rate
    local now = ngx_now() * 1000

    key = "limit_req" .. ":" .. key
    local excess_key = key .. "excess"
    local last_key = key .. "last"

    local excess, err = red:get(excess_key)
    if err then
        return nil, err
    end
    local last, err = red:get(last_key)
    if err then
        return nil, err
    end

    if excess ~= ngx_null and last ~= ngx_null then
        excess = tonumber(excess)
        last = tonumber(last)
        local elapsed = now - last
        excess = max(excess - rate * abs(elapsed) / 1000 + 1000, 0)

        if excess > self.burst then
            return nil, "rejected"
        end
    else
        excess = 0
    end

    if commit then
        local ok
        local err
        ok, err = red:set(excess_key, excess)
        if not ok then
            return nil, err
        end

        ok, err = red:set(last_key, now)
        if not ok then
            return nil, err
        end
    end

    -- return the delay in seconds, as well as excess
    return excess / rate, excess / 1000
end


return _M
