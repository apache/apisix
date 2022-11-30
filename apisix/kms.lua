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


local KMS_PREFIX = "$KMS://"
local kmss

local function check_kms(conf)
    local idx = find(conf.id or "", "/")
    if not idx then
        return false, "no kms id"
    end
    local service = sub(conf.id, 1, idx - 1)

    local ok, kms_service = pcall(require, "apisix.kms." .. service)
    if not ok then
        return false, "kms service not exits, service: " .. service
    end

    return core.schema.check(kms_service.schema, conf)
end


local kms_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local function create_kms_kvs(values)
    local kms_services = {}

    for _, v in ipairs(values) do
        local path = v.value.id
        local idx = find(path, "/")
        if not idx then
            core.log.error("no kms id")
            return nil
        end

        local service = sub(path, 1, idx - 1)
        local id = sub(path, idx + 1)

        if not kms_services[service] then
            kms_services[service] = {}
        end
        kms_services[service][id] = v.value
    end

    return kms_services
end


 local function kms_kv(service, confid)
    local kms_values
    kms_values = core.config.fetch_created_obj("/kms")
    if not kms_values or not kms_values.values then
       return nil
    end

    local kms_services = kms_lrucache("kms_kv", kms_values.conf_version,
            create_kms_kvs, kms_values.values)
    return kms_services[service] and kms_services[service][confid]
end


function _M.kmss()
    if not kmss then
        return nil, nil
    end

    return kmss.values, kmss.conf_version
end


function _M.init_worker()
    local cfg = {
        automatic = true,
        checker = check_kms,
    }

    kmss = core.config.new("/kms", cfg)
end


local function parse_kms_uri(kms_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    if type(kms_uri) ~= "string" then
        return nil, "error kms_uri type: " .. type(kms_uri)
    end

    if not string.has_prefix(upper(kms_uri), KMS_PREFIX) then
        return nil, "error kms_uri prefix: " .. kms_uri
    end

    local path = sub(kms_uri, #KMS_PREFIX + 1)
    local idx1 = find(path, "/")
    if not idx1 then
        return nil, "error format: no kms service"
    end
    local service = sub(path, 1, idx1 - 1)

    local idx2 = find(path, "/", idx1 + 1)
    if not idx2 then
        return nil, "error format: no kms conf id"
    end
    local confid = sub(path, idx1 + 1, idx2 - 1)

    local key = sub(path, idx2 + 1)
    if key == "" then
        return nil, "error format: no kms key id"
    end

    local opts = {
        service = service,
        confid = confid,
        key = key
    }
    return opts
end


local function fetch_by_uri(kms_uri)
    local opts, err = parse_kms_uri(kms_uri)
    if not opts then
        return nil, err
    end

    local conf = kms_kv(opts.service, opts.confid)
    if not conf then
        return nil, "no kms conf, kms_uri: " .. kms_uri
    end

    local ok, sm = pcall(require, "apisix.kms." .. opts.service)
    if not ok then
        return nil, "no kms service: " .. opts.service
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
    elseif string.has_prefix(upper(uri), KMS_PREFIX) then
        val, err = fetch_by_uri(uri)
    end

    if err then
        core.log.error("failed to fetch kms value: ", err)
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
