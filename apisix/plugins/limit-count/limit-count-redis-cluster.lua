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
local resty_lock = require("resty.lock")
local assert = assert
local setmetatable = setmetatable
local tostring = tostring


local _M = {version = 0.3}


local mt = {
    __index = _M
}

-- https://github.com/steve0511/resty-redis-cluster
local function new_redis_cluster(conf)
    local config = {
        dict_name = "redis_cluster_slot_locks", --shared dictionary name for locks
        name = "apisix-rediscluster",           --rediscluster name
        keepalive_timeout = 60000,              --redis connection pool idle timeout
        keepalive_cons = 1000,                  --redis connection pool size
        connect_timeout = 1000,                 --timeout while connecting
        max_redirection = 5,                    --maximum retry attempts for redirection
        max_connection_attempts = 1,            --maximum retry attempts for connection
        read_timeout = conf.redis_timeout or 1000,
        enable_slave_read = true,
        serv_list = {},
    }

    for key, value in ipairs(conf.redis_serv_list) do
        if value['redis_host'] and value['redis_port'] then
            config.serv_list[key] = {ip = value['redis_host'], port = value['redis_port']}
        end
    end

    if conf.redis_password then
        config.auth = conf.redis_password --set password while setting auth
    end
    
    local redis_cluster = require "resty.rediscluster"
    local red_c = redis_cluster:new(config)

    return red_c
end


function _M.new(plugin_name, limit, window, conf)
    assert(limit > 0 and window > 0)

    _M.red_c = new_redis_cluster(conf)

    local self = {limit = limit, window = window, conf = conf,
                  plugin_name = plugin_name}
    return setmetatable(self, mt)

end


function _M.incoming(self, key)
    local conf = self.conf
    local red = _M.red_c
    core.log.info("ttl key: ", key, " timeout: ", conf.redis_timeout or 1000)

    local limit = self.limit
    local window = self.window
    local remaining
    key = self.plugin_name .. tostring(key)

    local ret, err = red:ttl(key)
    if not ret then
        return false, "failed to get redis `" .. key .."` ttl: " .. err
    end

    core.log.info("ttl key: ", key, " ret: ", ret, " err: ", err)
    if ret < 0 then
        local lock, err = resty_lock:new("plugin-limit-count")
        if not lock then
            return false, "failed to create lock: " .. err
        end

        local elapsed, err = lock:lock(key)
        if not elapsed then
            return false, "failed to acquire the lock: " .. err
        end

        ret = red:ttl(key)
        if ret < 0 then
            local ok, err = lock:unlock()
            if not ok then
                return false, "failed to unlock: " .. err
            end

            ret, err = red:set(key, limit -1, "EX", window)
            if not ret then
                return nil, err
            end

            return 0, limit -1
        end

        local ok, err = lock:unlock()
        if not ok then
            return false, "failed to unlock: " .. err
        end
    end

    remaining, err = red:incrby(key, -1)
    if not remaining then
        return nil, err
    end

    if remaining < 0 then
        return nil, "rejected"
    end

    return 0, remaining
end


return _M
