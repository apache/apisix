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
local redis_new = require("resty.redis").new
local redis_sentinel = require("resty.redis.connector")
local to_hex = require("resty.string").to_hex
local crc32 = ngx.crc32_long
local _M = {}

local tostring = tostring

local commit_script = core.string.compress_script([=[
    assert(tonumber(ARGV[3]) >= 0, "cost must be at least 0")
    local ttl = redis.call('pttl', KEYS[1])
    if ttl < 0 then
        redis.call('set', KEYS[1], ARGV[3], 'EX', ARGV[2])
        return {ARGV[3], ARGV[2] * 1000}
    end
    return {redis.call('incrby', KEYS[1], ARGV[3]), ttl}
]=])
local commit_script_sha = to_hex(ngx.sha1_bin(commit_script))


function _M.redis_cli(conf)
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- 1sec

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
        return nil, err
    end

    local count
    count, err = red:get_reused_times()
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
        if (conf.redis_database or 0) ~= 0 then
            local ok, err = red:select(conf.redis_database)
            if not ok then
                return nil, "failed to change redis db, err: " .. err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end
    return red, nil
end

function _M.redis_cli_sentinel(conf)
    local redis_conf = {
        username = conf.redis_username,
        password = conf.redis_password,
        sentinel_username = conf.sentinel_username,
        sentinel_password = conf.sentinel_password,
        db = conf.redis_database or 0,
        sentinels = conf.redis_sentinels or {},
        master_name = conf.redis_master_name,
        role = conf.redis_role or "master",
        connect_timeout = conf.redis_connect_timeout or 1000,
        read_timeout = conf.redis_read_timeout or 1000,
        keepalive_timeout = conf.redis_keepalive_timeout or 60000,
    }

    local sentinel_client, err = redis_sentinel.new(redis_conf)
    if not sentinel_client then
        return nil, "failed to create redis client: " .. (err or "unknown error")
    end

    -- In case of errors, returns "nil, err, previous_errors" where err is
    -- the last error received, and previous_errors is a table of the previous errors.
    local red, err, previous_errors = sentinel_client:connect()
    if not red then
        local err = "redis connection failed, err: " .. (err or "unknown error")
        if previous_errors and #previous_errors > 0 then
            err = err .. ", previous_errors: " .. core.table.concat(previous_errors, ", ")
        end
        return nil, err
    end
    return red, nil
end


function _M.redis_incoming(self, key, cost, keepalive)
    if self.window_type == "sliding" then
        return self.limit_count:incoming(key, cost)
    end

    local red = self.red_cli
    if not red then
        return nil, "redis client not initialized", 0
    end

    local limit = self.limit
    local window = self.window
    -- The fixed-window counter stores the consumed count and increments it;
    -- earlier releases stored the remaining quota and decremented it on the same
    -- key. When a storage-format version is set, embed it in the key so the two
    -- formats never share a key across an upgrade (which would over- or
    -- under-limit the route); old keys just expire via their own TTL. Backends
    -- created without a key_version (e.g. direct unit-test use) keep the
    -- original unversioned key.
    if self.key_version then
        key = self.plugin_name .. ":" .. self.key_version .. ":" .. tostring(key)
    else
        key = self.plugin_name .. tostring(key)
    end

    core.log.info("syncing limit count to redis, key: ", key,
                    ", limit: ", limit, ", window: ", window, ", cost: ", cost)

    local res, err
    res, err = red:evalsha(commit_script_sha, 1, key, limit, window, cost)
    if err and core.string.has_prefix(err, "NOSCRIPT") then
        core.log.warn("redis evalsha failed: ", err, ". Falling back to eval")
        res, err = red:eval(commit_script, 1, key, limit, window, cost)
    end
    if err then
        return nil, err, 0
    end

    local remaining = limit - res[1]
    local ttl = res[2] / 1000.0

    if keepalive then
        local conf = self.conf or {}
        local ok, err = red:set_keepalive(conf.redis_keepalive_timeout or 10000,
                                          conf.redis_keepalive_pool or 100)
        if not ok then
            core.log.error("failed to set keepalive for redis: ", err)
        end
    end


    if remaining < 0 then
        return nil, "rejected", ttl
    end

    return 0, remaining, ttl
end


return _M
