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

local find  = string.find
local sub   = string.sub
local upper = string.upper
local type = type

local _M = {
    version = 0.1,
}


local KMS_PREFIX = "$KMS://"
local kmss

local function check_kms(conf)
    --core.log.warn("check path: ", path, " :", require("inspect")(conf))

    local idx = find(conf.id or "", "/")
    if not idx then
        return false, "no kms id"
    end
    local service = sub(conf.id, 1, idx - 1)

    local ok = pcall(require, "apisix.kms." .. service)
    if not ok then
        return false, "kms service not exits, service: " .. service
    end

    return core.schema.check(core.schema["kms_" .. service], conf)
end


local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local function create_kms_kvs(values)
    local kms_services = {}

    for _, v in ipairs(values) do
        local path = v.value.id
        local idx = find(path, "/")
        if not idx then
            core.log.error("no kms id")
            return
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
    if not kms_values then
       return nil
    end
    --core.log.warn("check path: ", confid, " :", require("inspect")(kms_kv))
    local kms_services = lrucache("kms_kv", kms_values.conf_version, create_kms_kvs, kms_values.values)
    --core.log.warn("hhget: ", require("inspect")(kms_services))
    return kms_services[service] and kms_services[service][confid] or nil
end


function _M.kmss()
    if not kmss then
        return nil, nil
    end

    return kmss.values, kmss.conf_version
end


function _M.init_worker()
    local err
    local cfg = {
        automatic = true,
        checker = check_kms,
    }

    kmss, err = core.config.new("/kms", cfg)
    if not kmss then
        error("failed to create etcd instance for fetching kmss: " .. err)
        return
    end
end


local function is_kms_uri(kms_uri)
    -- Avoid the error caused by has_prefix to cause a crash.
    return type(kms_uri) == "string" and
        string.has_prefix(upper(kms_uri), KMS_PREFIX)
end


local function parse_kms_uri(kms_uri)
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
    return opts, nil
end


function _M.get(kms_uri)
    if not is_kms_uri(kms_uri) then
        return nil
    end
    local opts, err = parse_kms_uri(kms_uri)
    if not opts then
        core.log.warn(err)
        return nil
    end
    local conf = kms_kv(opts.service, opts.confid)
    if not conf then
        core.log.error("no config")
        return nil
    end
    local sm = require("apisix.kms." .. opts.service)
    if not sm then
        core.log.error("no kms service: ", opts.service)
        return nil
    end
    local value, err = sm.get(conf, opts.key)
    if err then
        core.log.error(err)
        return nil
    end
    return value
end


return _M
