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

local require   = require
local core      = require("apisix.core")
local string    = require("apisix.core.string")

local local_conf = require("apisix.core.config_local").local_conf()

local find      = string.find
local sub       = string.sub
local upper     = string.upper
local byte      = string.byte
local type      = type
local pcall     = pcall
local pairs     = pairs

local _M = {}


local PREFIX = "$secret://"
local secrets

local function check_secret(conf)
    local idx = find(conf.id or "", "/")
    if not idx then
        return false, "no secret id"
    end
    local manager = sub(conf.id, 1, idx - 1)

    local ok, secret_manager = pcall(require, "apisix.secret." .. manager)
    if not ok then
        return false, "secret manager not exits, manager: " .. manager
    end

    return core.schema.check(secret_manager.schema, conf)
end


local function secret_kv(manager, confid)
    local secret_values
    secret_values = core.config.fetch_created_obj("/secrets")
    if not secret_values or not secret_values.values then
       return nil
    end

    local secret = secret_values:get(manager .. "/" .. confid)
    if not secret then
        return nil
    end

    return secret.value
end


function _M.secrets()
    if not secrets then
        return nil, nil
    end

    return secrets.values, secrets.conf_version
end


function _M.init_worker()
    local cfg = {
        automatic = true,
        checker = check_secret,
    }

    secrets = core.config.new("/secrets", cfg)
end


local function check_secret_uri(secret_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    if type(secret_uri) ~= "string" then
        return false, "error secret_uri type: " .. type(secret_uri)
    end

    if not string.has_prefix(secret_uri, PREFIX) and
        not string.has_prefix(upper(secret_uri), core.env.PREFIX) then
        return false, "error secret_uri prefix: " .. secret_uri
    end

    return true
end

_M.check_secret_uri = check_secret_uri


local function parse_secret_uri(secret_uri)
    local is_secret_uri, err = check_secret_uri(secret_uri)
    if not is_secret_uri then
        return is_secret_uri, err
    end

    local path = sub(secret_uri, #PREFIX + 1)
    local idx1 = find(path, "/")
    if not idx1 then
        return nil, "error format: no secret manager"
    end
    local manager = sub(path, 1, idx1 - 1)

    local idx2 = find(path, "/", idx1 + 1)
    if not idx2 then
        return nil, "error format: no secret conf id"
    end
    local confid = sub(path, idx1 + 1, idx2 - 1)

    local key = sub(path, idx2 + 1)
    if key == "" then
        return nil, "error format: no secret key id"
    end

    local opts = {
        manager = manager,
        confid = confid,
        key = key
    }
    return opts
end


local function fetch_by_uri(secret_uri)
    core.log.info("fetching data from secret uri: ", secret_uri)
    local opts, err = parse_secret_uri(secret_uri)
    if not opts then
        return nil, err
    end

    local conf = secret_kv(opts.manager, opts.confid)
    if not conf then
        return nil, "no secret conf, secret_uri: " .. secret_uri
    end

    local ok, sm = pcall(require, "apisix.secret." .. opts.manager)
    if not ok then
        return nil, "no secret manager: " .. opts.manager
    end

    local value, err = sm.get(conf, opts.key)
    if err then
        return nil, err
    end

    return value
end

-- for test
_M.fetch_by_uri = fetch_by_uri

-- Create separate LRU caches for success and failure
local function new_lrucache(cache_type)
    local base_path = {"apisix", "lru", "secret", cache_type, "ttl"}
    local ttl = core.table.try_read_attr(local_conf, unpack(base_path)) or
                core.table.try_read_attr(local_conf, "apisix", "lru", "secret", "ttl")

    if not ttl then
        ttl = cache_type == "success" and 300 or 60 -- 5min success, 1min failure default
    end

    local count = core.table.try_read_attr(local_conf, "apisix", "lru", "secret", "count")
    if not count then
        count = 512
    end

    core.log.info("secret ", cache_type, " lrucache ttl: ", ttl, ", count: ", count)
    return core.lrucache.new({
        ttl = ttl, count = count, invalid_stale = true, refresh_stale = true
    })
end

local secrets_success_cache = new_lrucache("success")
local secrets_failure_cache = new_lrucache("failure")

-- cache-aware fetch function
local function fetch(uri, use_cache)
    -- do a quick filter to improve retrieval speed
    if byte(uri, 1, 1) ~= byte('$') then
        return nil
    end

    -- Check cache first if enabled
    if use_cache then
        local cached_success = secrets_success_cache(uri)
        if cached_success then
            return cached_success
        end

        local cached_failure = secrets_failure_cache(uri)
        if cached_failure then
            return nil
        end
    end

    local val, err
    if string.has_prefix(upper(uri), core.env.PREFIX) then
        val, err = core.env.fetch_by_uri(uri)
    elseif string.has_prefix(uri, PREFIX) then
        val, err = fetch_by_uri(uri)
    end

    if err then
        core.log.error("failed to fetch secret value: ", err)
        if use_cache then
            secrets_failure_cache(uri, true) -- cache the failure
        end
        return nil
    end

    if val and use_cache then
        secrets_success_cache(uri, val) -- cache the success
    end

    return val
end


local function retrieve_refs(refs, use_cache)
    for k, v in pairs(refs) do
        local typ = type(v)
        if typ == "string" then
            refs[k] = fetch(v, use_cache) or v
        elseif typ == "table" then
            retrieve_refs(v, use_cache)
        end
    end
    return refs
end

function _M.fetch_secrets(refs, use_cache)
    if not refs or type(refs) ~= "table" then
        return nil
    end

    local new_refs = core.table.deepcopy(refs)
    return retrieve_refs(new_refs, use_cache)
end

return _M
