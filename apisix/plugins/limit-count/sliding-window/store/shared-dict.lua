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
local ngx = ngx
local log = require("apisix.core.log")
local string_format = string.format
local setmetatable = setmetatable

local _M = {}
local mt = { __index = _M }

function _M.new(options)
    if not options.name then
        return nil, "shared dictionary name is mandatory"
    end

    local dict = ngx.shared[options.name]
    if not dict then
        return nil,
            string_format("shared dictionary with name \"%s\" is not configured",
                options.name)
    end

    return setmetatable({
        dict = dict,
    }, mt)
end

function _M.incr(self, key, delta, expiry)
    local new_value, err, forcible = self.dict:incr(key, delta, 0, expiry)
    if err then
        return nil, err
    end

    if forcible then
        log.warn("shared dictionary is full, removed valid key(s) to store the new one")
    end

    return new_value
end

-- Counterpart of the redis store's atomic check. Shared dict ops don't yield,
-- so get/decide/incr can't interleave within a worker. They aren't atomic
-- across workers though, so a concurrent burst may admit a few extra requests
-- at a window boundary. Best-effort by design; the redis store is exact.
function _M.check_and_incr(self, current_key, last_key, cost, limit,
                           window_size, remaining_time, expiry)
    local dict = self.dict
    local last = dict:get(last_key) or 0
    if last > limit then
        last = limit
    end

    local cur = dict:get(current_key) or 0
    local estimated = last / window_size * remaining_time + cur
    if cur >= limit or estimated >= limit then
        return {0, cur, last}
    end

    local new, err, forcible = dict:incr(current_key, cost, 0, expiry)
    if err then
        return nil, err
    end

    if forcible then
        log.warn("shared dictionary is full, removed valid key(s) to store the new one")
    end

    return {1, new, last}
end

function _M.get(self, key)
    local value, err = self.dict:get(key)
    if not value then
        return nil, err
    end

    return value
end

return _M
