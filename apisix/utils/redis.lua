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
local redis_new     = require("resty.redis").new
local core          = require("apisix.core")
local crc32         = ngx.crc32_long


local _M = {version = 0.1}

local function redis_cli(conf)
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- default 1sec

    red:set_timeouts(timeout, timeout, timeout)

    -- AUTH, SELECT and the TLS handshake are run only on fresh connections,
    -- so connections with different databases, credentials or TLS settings
    -- must not share the default host:port keepalive pool, otherwise a
    -- reused connection may be bound to an unexpected database or user, or
    -- skip the expected certificate verification
    local scheme = "redis"
    if conf.redis_ssl then
        scheme = conf.redis_ssl_verify and "rediss-verify" or "rediss"
    end
    local pool = scheme .. "#" .. conf.redis_host .. "#" .. (conf.redis_port or 6379)
                 .. "#" .. (conf.redis_database or 0)
    if conf.redis_password and conf.redis_password ~= '' then
        -- digest instead of the plaintext credentials in the pool name
        pool = pool .. "#" .. crc32((conf.redis_username or "") .. ":" .. conf.redis_password)
    end

    local sock_opts = {
        ssl = conf.redis_ssl,
        ssl_verify = conf.redis_ssl_verify,
        pool = pool,
    }

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379, sock_opts)
    if not ok then
        core.log.error(" redis connect error, error: ", err)
        return false, err
    end

    local count
    count, err = red:get_reused_times()
    core.log.debug("redis connection reused times: ", count)
    if 0 == count then
        if conf.redis_password and conf.redis_password ~= '' then
            local ok, err
            if conf.redis_username then
                ok, err = red:auth(conf.redis_username, conf.redis_password)
            else
                ok, err = red:auth(conf.redis_password)
            end
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


function _M.new(conf)
    return redis_cli(conf)
end

return _M
