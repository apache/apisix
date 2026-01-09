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
local ngx = ngx
local get_phase = ngx.get_phase
local setmetatable = setmetatable
local util = require("apisix.plugins.limit-count.util")
local ngx_timer_at = ngx.timer.at

local _M = {}


local mt = {
    __index = _M
}


function _M.new(plugin_name, limit, window, conf)
    local red_cli, err = redis_cluster.new(conf, "plugin-limit-count-redis-cluster-slot-lock")
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


local function log_phase_incoming_thread(premature, self, key, cost)
    return util.redis_log_phase_incoming(self, self.red_cli, key, cost)
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

        return 0, self.limit, self.window
    end

    return util.redis_incoming(self, self.red_cli, key, not dry_run, cost)
end


return _M
