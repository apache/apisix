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

--- Instance id of APISIX
--
-- @module core.id

local fetch_local_conf = require("apisix.core.config_local").local_conf
local try_read_attr    = require("apisix.core.table").try_read_attr
local profile          = require("apisix.core.profile")
local log              = require("apisix.core.log")
local uuid             = require("resty.jit-uuid")
local smatch           = string.match
local open             = io.open
local type             = type
local ipairs           = ipairs
local string           = string
local math             = math
local prefix           = ngx.config.prefix()
local apisix_uid

local _M = {version = 0.1}


local function rtrim(str)
    return smatch(str, "^(.-)%s*$")
end


local function read_file(path)
    local file = open(path, "rb") -- r read mode and b binary mode
    if not file then
        return nil
    end

    local content = file:read("*a")  -- *a or *all reads the whole file
    file:close()
    return rtrim(content)
end


local function write_file(path, data)
    local file = open(path, "w+")
    if not file then
        return nil, "failed to open file[" .. path .. "] for writing"
    end

    file:write(data)
    file:close()
    return true
end


_M.gen_uuid_v4 = uuid.generate_v4


--- This will autogenerate the admin key if it's passed as an empty string in the configuration.
local function autogenerate_admin_key(default_conf)
    local changed = false
    local generated_key = ""
   -- Check if deployment.role is either traditional or control_plane
    local deployment_role = default_conf.deployment and default_conf.deployment.role
    if deployment_role and (deployment_role == "traditional" or
       deployment_role == "control_plane") then
        -- Check if deployment.admin.admin_key is not nil and it's an empty string
        local admin_keys = try_read_attr(default_conf, "deployment", "admin", "admin_key")
        if admin_keys and type(admin_keys) == "table" then
            for i, admin_key in ipairs(admin_keys) do
                if admin_key.role == "admin" and admin_key.key == "" then
                    changed = true
                    for _ = 1, 32 do
                        generated_key = generated_key ..
                        string.char(math.random(65, 90) + math.random(0, 1) * 32)
                    end
                    admin_keys[i].key = generated_key
                end
            end
        end
    end
    return default_conf, changed, generated_key
end


function _M.init()
    local local_conf = fetch_local_conf()

    local local_conf, changed, generated_key = autogenerate_admin_key(local_conf)
    if changed then
        log.warn("admin key was not set, a key has been auto-generated: ", generated_key,
                 " -- it is recommended to set a permanent key in conf/config.yaml")

        local local_conf_path = profile:yaml_path("config")
        local content = read_file(local_conf_path)
        if content then
            local new_content, n = content:gsub("key: ''", "key: " .. generated_key, 1)
            if n == 0 then
                new_content, n = new_content:gsub('key: ""', "key: " .. generated_key, 1)
            end
            if n > 0 then
                local ok, err = write_file(local_conf_path, new_content)
                if not ok then
                    log.warn("failed to write auto-generated admin_key to config.yaml: ", err)
                end
            else
                log.warn("could not write generated admin_key to config.yaml, " ..
                         "please set it manually: ", generated_key)
            end
        end
    end

    --allow user to specify a meaningful id as apisix instance id
    local uid_file_path = prefix .. "/conf/apisix.uid"
    apisix_uid = read_file(uid_file_path)
    if apisix_uid then
        return
    end

    local id = try_read_attr(local_conf, "apisix", "id")
    if id then
        apisix_uid = local_conf.apisix.id
    else
        uuid.seed()
        apisix_uid = uuid.generate_v4()
        log.notice("not found apisix uid, generate a new one: ", apisix_uid)
    end

    local ok, err = write_file(uid_file_path, apisix_uid)
    if not ok then
        log.error(err)
    end
end


---
-- Returns the instance id of the running APISIX
--
-- @function core.id.get
-- @treturn string the instance id
-- @usage
-- local apisix_id = core.id.get()
function _M.get()
    return apisix_uid
end

return _M
