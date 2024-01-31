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
local redis         = require("apisix.utils.redis")
local core          = require("apisix.core")
local util          = require("apisix.plugins.limit-conn.util")
local ngx_timer_at  = ngx.timer.at

local setmetatable  = setmetatable


local _M = {version = 0.1}


local mt = {
    __index = _M
}

function _M.new(plugin_name, conf, max, burst, default_conn_delay)

    local self = {
        conf = conf,
        plugin_name = plugin_name,
        burst = burst,
        max = max + 0,    -- just to ensure the param is good
        unit_delay = default_conn_delay,
    }
    return setmetatable(self, mt)
end


function _M.incoming(self, key, commit)
    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err
    end
    return util.incoming(self, red, key, commit)
end


function _M.is_committed(self)
    return self.committed
end


local function leaving_thread(premature, self, key, req_latency)

    local conf = self.conf
    local red, err = redis.new(conf)
    if not red then
        return red, err
    end
    return util.leaving(self, red, key, req_latency)
end


function _M.leaving(self, key, req_latency)
    -- log_by_lua can't use cosocket
    local ok, err = ngx_timer_at(0, leaving_thread, self, key, req_latency)
    if not ok then
        core.log.error("failed to create timer: ", err)
        return nil, err
    end

    return ok

end



return _M
