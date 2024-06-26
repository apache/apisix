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
local redis     = require("apisix.utils.redis")
local core = require("apisix.core")
local delayed_syncer = require("apisix.plugins.limit-count.delayed_syncer")

local assert = assert
local setmetatable = setmetatable
local tostring = tostring
local ngx_shared = ngx.shared


local _M = {version = 0.3}


local mt = {
    __index = _M
}

local to_be_synced = {}
local redis_confs = {}

local script = core.string.compress_script([=[
    local ttl = redis.call('ttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1] - ARGV[3], 'EX', ARGV[2])
        return {ARGV[1] - ARGV[3], ARGV[2]}
    end
    return {redis.call('incrby', KEYS[1], 0 - ARGV[3]), ttl}
]=])



function _M.new(plugin_name, limit, window, conf)
    assert(limit > 0 and window > 0)

    local self = {
        limit = limit,
        window = window,
        conf = conf,
        plugin_name = plugin_name,
        counter = ngx_shared["plugin-limit-count-redis-counter"],
    }
    return setmetatable(self, mt)
end


function _M.incoming(self, key, cost)
    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err, 0
    end

    local limit = self.limit
    local window = self.window
    local res
    key = self.plugin_name .. tostring(key)

    local counter = self.counter

    if conf.sync_interval ~= -1 then
        local delay, remaining, ttl = delayed_syncer.rate_limit_with_delayed_sync(conf, counter,
                                      to_be_synced, redis_confs, key, cost, limit, window, script)
        return delay, remaining, ttl
    end
    local ttl = 0
    res, err = red:eval(script, 1, key, limit, window, cost or 1)

    if err then
        return nil, err, ttl
    end

    local remaining = res[1]
    ttl = res[2]

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err, ttl
    end

    if remaining < 0 then
        return nil, "rejected", ttl
    end
    return 0, remaining, ttl
end


function _M.destroy()
    delayed_syncer.redis_syncer_stop()
end

return _M
