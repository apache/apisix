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

--- Load and validates admin keys.
--
-- @module core.admin_key

local fetch_local_conf = require("apisix.core.config_local").local_conf
local try_read_attr    = require("apisix.core.table").try_read_attr
local log              = require("apisix.core.log")
local ngx_exit         = ngx.exit

local _M = {}

function _M.init()
    local local_conf = fetch_local_conf()

    -- Check if local_conf is valid
    if not local_conf then
        log.error("admin_key: local configuration not available")
        return
    end

    -- Check if we're in a deployment role that needs admin keys
    local deployment_role = local_conf.deployment and local_conf.deployment.role
    if not deployment_role or (deployment_role ~= "traditional" and
                              deployment_role ~= "control_plane") then
        return
    end

    -- Check the admin_key_required configuration setting
    if local_conf.deployment.admin and local_conf.deployment.admin.admin_key_required == false then
        return
    end

    -- Get admin keys from configuration
    local admin_keys = try_read_attr(local_conf, "deployment", "admin", "admin_key")
    if not admin_keys or #admin_keys == 0 then
        -- No admin keys configured but admin_key_required is true
        log.error("admin_key: admin keys are required but none are configured. " ..
                  "Please set admin_key values in conf/config.yaml")
        ngx_exit(1)
    end

    -- Check if any admin keys have empty values
    for _, admin_key in ipairs(admin_keys) do
        if admin_key.role == "admin" and admin_key.key == "" then
            log.error("admin_key: empty admin API key detected. " ..
                      "APISIX cannot start with empty admin keys when admin_key_required is true.")
            log.error("admin_key: please set proper admin_key values in conf/config.yaml")
            ngx_exit(1)
        end
    end
end

return _M
