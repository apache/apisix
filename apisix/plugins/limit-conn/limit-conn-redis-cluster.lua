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
local redis_cluster     = require("apisix.utils.rediscluster")
local core              = require("apisix.core")
local assert            = assert
local setmetatable      = setmetatable
local math              = require "math"
local floor             = math.floor
local ngx_timer_at      = ngx.timer.at

local _M = {version = 0.1}


local mt = {
    __index = _M
}


function _M.new(plugin_name, conf, max, burst, default_conn_delay)

    local red_cli, err = redis_cluster.new(conf, "plugin-limit-conn-redis-cluster-slot-lock")
    if not red_cli then
        return nil, err
    end
    local self = {
        conf = conf,
        plugin_name = plugin_name,
        burst = burst,
        max = max + 0,    -- just to ensure the param is good
        unit_delay = default_conn_delay,
        red_cli = red_cli,
    }
    return setmetatable(self, mt)
end


function _M.incoming(self, key, commit)
    local max = self.max
    local red = self.red_cli

    self.committed = false

    local hash_key = "limit_conn"

    local conn, err
    if commit then
        conn, err = red:hincrby(hash_key, key, 1)
        if not conn then
            return nil, err
        end

        if conn > max + self.burst then
            conn, err = red:hincrby(hash_key, key, -1)
            if not conn then
                return nil, err
            end
            return nil, "rejected"
        end
        self.committed = true

    else
        local conn_from_red, err = red:hget(hash_key, key)
        if err then
            return nil, err
        end
        conn = (conn_from_red or 0) + 1
    end

    if conn > max then
        -- make the excessive connections wait
        return self.unit_delay * floor((conn - 1) / max), conn
    end

    -- we return a 0 delay by default
    return 0, conn
end


function _M.is_committed(self)
    return self.committed
end


local function leaving_thread(premature, self, key, req_latency)

    local red = self.red_cli

    local hash_key = "limit_conn"

    local conn, err = red:hincrby(hash_key, key, -1)
    if not conn then
        return nil, err
    end

    if req_latency then
        local unit_delay = self.unit_delay
        self.unit_delay = (req_latency + unit_delay) / 2
    end

    return conn
end


function _M.leaving(self, key, req_latency)
    assert(key)

    -- log_by_lua can't use cosocket
    local ok, err = ngx_timer_at(0, leaving_thread, self, key, req_latency)
    if not ok then
        core.log.error("failed to create timer: ", err)
        return nil, err
    end

    return ok

end



return _M
