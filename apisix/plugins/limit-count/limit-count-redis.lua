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
local ngx = ngx
local get_phase = ngx.get_phase
local assert = assert
local setmetatable = setmetatable
local util = require("apisix.plugins.limit-count.util")
local ngx_timer_at = ngx.timer.at


local _M = {version = 0.3}


local mt = {
    __index = _M
}


function _M.new(plugin_name, limit, window, conf)
    assert(limit > 0 and window > 0)

    local self = {
        limit = limit,
        window = window,
        conf = conf,
        plugin_name = plugin_name,
    }
    return setmetatable(self, mt)
end


local function log_phase_incoming_thread(premature, self, key, cost)
    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err
    end
    return util.redis_log_phase_incoming(self, red, key, cost)
end


local function log_phase_incoming(self, key, cost, dry_run)
    if dry_run then
        return true
    end

    local ok, err = ngx_timer_at(0, log_phase_incoming_thread, self, key, cost)
    if not ok then
        core.log.error("failed to create timer: ", err)
        return nil, err
    end

    return ok
end


function _M.incoming(self, key, cost, dry_run)
    if get_phase() == "log" then
        local ok, err = log_phase_incoming(self, key, cost, dry_run)
        if not ok then
            return nil, err, 0
        end

        -- best-effort result because lua-resty-redis is not allowed in log phase
        return 0, self.limit, self.window
    end

    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err, 0
    end

    local delay, remaining, ttl = util.redis_incoming(self, red, key, not dry_run, cost)
    if not delay then
        local err = remaining
        return nil, err, ttl or 0
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err, ttl
    end

    return delay, remaining, ttl
end


return _M
