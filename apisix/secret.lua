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

local find      = string.find
local sub       = string.sub
local upper     = string.upper
local byte      = string.byte
local type      = type
local pcall     = pcall
local pairs     = pairs
local ipairs    = ipairs

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


local secret_kv_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local function create_secret_kvs(values)
    local secret_managers = {}

    for _, v in ipairs(values) do
        local path = v.value.id
        local idx = find(path, "/")
        if not idx then
            core.log.error("no secret id")
            return nil
        end

        local manager = sub(path, 1, idx - 1)
        local id = sub(path, idx + 1)

        if not secret_managers[manager] then
            secret_managers[manager] = {}
        end
        secret_managers[manager][id] = v.value
    end

    return secret_managers
end


 local function secret_kv(manager, confid)
    local secret_values
    secret_values = core.config.fetch_created_obj("/secrets")
    if not secret_values or not secret_values.values then
       return nil
    end

    local secret_managers = secret_kv_lrucache("secret_kv", secret_values.conf_version,
                create_secret_kvs, secret_values.values)
    return secret_managers[manager] and secret_managers[manager][confid]
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


local function parse_secret_uri(secret_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    if type(secret_uri) ~= "string" then
        return nil, "error secret_uri type: " .. type(secret_uri)
    end

    if not string.has_prefix(secret_uri, PREFIX) then
        return nil, "error secret_uri prefix: " .. secret_uri
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


local function fetch(uri)
    -- do a quick filter to improve retrieval speed
    if byte(uri, 1, 1) ~= byte('$') then
        return nil
    end

    local val, err
    if string.has_prefix(upper(uri), core.env.PREFIX) then
        val, err = core.env.fetch_by_uri(uri)
    elseif string.has_prefix(uri, PREFIX) then
        val, err = fetch_by_uri(uri)
    end

    if err then
        core.log.error("failed to fetch secret value: ", err)
        return
    end

    return val
end


local secrets_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local fetch_secrets
do
    local retrieve_refs
    function retrieve_refs(refs)
        for k, v in pairs(refs) do
            local typ = type(v)
            if typ == "string" then
                refs[k] = fetch(v) or v
            elseif typ == "table" then
                retrieve_refs(v)
            end
        end
        return refs
    end

    local function retrieve(refs)
        core.log.info("retrieve secrets refs")

        local new_refs = core.table.deepcopy(refs)
        return retrieve_refs(new_refs)
    end

    function fetch_secrets(refs, cache, key, version)
        if not refs or type(refs) ~= "table" then
            return nil
        end
        if not cache then
            return retrieve(refs)
        end
        return secrets_lrucache(key, version, retrieve, refs)
    end
end

_M.fetch_secrets = fetch_secrets

return _M
