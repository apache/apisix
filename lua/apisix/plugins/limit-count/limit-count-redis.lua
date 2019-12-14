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
local redis_new = require("resty.redis").new
local core = require("apisix.core")
local assert = assert
local setmetatable = setmetatable
local tostring = tostring


local _M = {version = 0.2}


local mt = {
    __index = _M
}


function _M.new(plugin_name, limit, window, conf)
    assert(limit > 0 and window > 0)

    local self = {limit = limit, window = window, conf = conf,
                  plugin_name = plugin_name}
    return setmetatable(self, mt)
end


function _M.incoming(self, key)
    local conf = self.conf
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- 1sec
    core.log.info("ttl key: ", key, " timeout: ", timeout)

    red:set_timeouts(timeout, timeout, timeout)

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379)
    if not ok then
        return false, err
    end

    local limit = self.limit
    local window = self.window
    local remaining
    key = self.plugin_name .. tostring(key)

    local ret, err = red:ttl(key)
    core.log.info("ttl key: ", key, " ret: ", ret, " err: ", err)
    if ret < 0 then
        ret, err = red:set(key, limit -1, "EX", window, "NX")
        if not ret then
            return nil, err
        end

        return 0, limit -1
    end

    remaining, err = red:incrby(key, -1)
    if not remaining then
        return nil, err
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err
    end

    if remaining < 0 then
        return nil, "rejected"
    end

    return 0, remaining
end


return _M
