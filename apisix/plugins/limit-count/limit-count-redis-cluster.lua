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

local _M = {}


local mt = {
    __index = _M
}


local script = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 1, "cost must be at least 1")
    local ttl = redis.call('ttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1] - ARGV[3], 'EX', ARGV[2])
        return {ARGV[1] - ARGV[3], ARGV[2]}
    end
    return {redis.call('incrby', KEYS[1], 0 - ARGV[3]), ttl}
]=])


function _M.new(plugin_name, limit, window, conf)
    local red_cli, err = redis_cluster.new(conf)
    if not red_cli then
        return nil, err
    end

    local self = {
        limit = limit,
        window = window,
        conf = conf,
        plugin_name = plugin_name,
        red_cli = red_cli,
    }

    return setmetatable(self, mt)
end


function _M.incoming(self, key, cost)
    local red = self.red_cli
    local limit = self.limit
    local window = self.window
    key = self.plugin_name .. tostring(key)

    local ttl = 0
    local res, err = red:eval(script, 1, key, limit, window, cost or 1)

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
