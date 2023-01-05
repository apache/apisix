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


local _M = {version = 0.3}


local mt = {
    __index = _M
}


local script = core.string.compress_script([=[
    local ttl = redis.call('ttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[1] - 1, 'EX', ARGV[2])
        return {ARGV[1] - 1, ARGV[2]}
    end
    return {redis.call('incrby', KEYS[1], -1), ttl}
]=])

local function redis_cli(conf)
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- 1sec

    red:set_timeouts(timeout, timeout, timeout)

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379)
    if not ok then
        return false, err
    end

    local count
    count, err = red:get_reused_times()
    if 0 == count then
        if conf.redis_password and conf.redis_password ~= '' then
            local ok, err = red:auth(conf.redis_password)
            if not ok then
                return nil, err
            end
        end

        -- select db
        if conf.redis_database ~= 0 then
            local ok, err = red:select(conf.redis_database)
            if not ok then
                return false, "failed to change redis db, err: " .. err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end
    return red, nil
end

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

function _M.incoming(self, key)
    local conf = self.conf
    local red, err = redis_cli(conf)
    if not red then
        return red, err, 0
    end

    local limit = self.limit
    local window = self.window
    local res
    key = self.plugin_name .. tostring(key)

    local ttl = 0
    res, err = red:eval(script, 1, key, limit, window)

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


return _M
