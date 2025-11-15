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
local core = require("apisix.core")
local _M = {version = 0.1}

local commit_script = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 1, "cost must be at least 1")
    local ttl = redis.call('ttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1] - ARGV[3], 'EX', ARGV[2])
        return {ARGV[1] - ARGV[3], ARGV[2]}
    end
    return {redis.call('incrby', KEYS[1], 0 - ARGV[3]), ttl}
]=])

local peek_script = core.string.compress_script([=[
    local ttl = redis.call('ttl', KEYS[1])
    local limit = tonumber(ARGV[1])
    local cost = tonumber(ARGV[3])
    if ttl < 0 then
        return {limit - cost, tonumber(ARGV[2])}
    end
    local current = redis.call('get', KEYS[1])
    if not current then
        return {limit - cost, tonumber(ARGV[2])}
    end
    return {tonumber(current) - cost, ttl}
]=])

function _M.incoming(self, red, key, commit, cost)
    local limit = self.limit
    local window = self.window
    key = self.plugin_name .. tostring(key)

    local ttl = 0
    local script = commit and commit_script or peek_script
    local res, err = red:eval(script, 1, key, limit, window, cost or 1)

    if err then
        return nil, err, ttl
    end

    local remaining = tonumber(res[1])
    if not remaining then
        local step = cost or 1
        remaining = commit and (limit - step) or (limit - step)
    end
    ttl = tonumber(res[2]) or window

    if remaining < 0 then
        return nil, "rejected", ttl
    end

    return 0, remaining, ttl
end

function _M.log_phase_incoming(self, red, key, cost)
    local limit = self.limit
    local window = self.window
    key = self.plugin_name .. tostring(key)

    local res, err = red:eval(commit_script, 1, key, limit, window, cost or 1)
    if err then
        return nil, err
    end

    return res[1]
end

return _M

