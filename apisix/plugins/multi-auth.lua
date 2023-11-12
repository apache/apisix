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

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        auth_plugins = { type = "array", minItems = 2 },
        hide_credentials = {
            type = "boolean",
            default = false,
        }
    },
    required = { "auth_plugins" },
}


local plugin_name = "multi-auth"

local _M = {
    version = 0.1,
    priority = 2600,
    type = 'auth',
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local auth_plugins = conf.auth_plugins
    for k, auth_plugin in pairs(auth_plugins) do
        for key, value in pairs(auth_plugin) do
            local auth = require("apisix.plugins." .. key)
            if auth == nil then
                return false, key .. " plugin did not found"
                else
                if auth.type ~= 'auth' then
                    return false, key .. " plugin is not supported"
                end
            end
        end
    end

    return true
end

function _M.rewrite(conf, ctx)
    local auth_plugins = conf.auth_plugins
    local status_code
    for k, auth_plugin in pairs(auth_plugins) do
        for key, value in pairs(auth_plugin) do
            local auth = require("apisix.plugins." .. key)
            local auth_code = auth.rewrite(value, ctx)
            status_code = auth_code
            if auth_code == nil then
                core.log.debug("Authentication is successful" .. key .. " plugin")
                goto authenticated
            else
                core.log.warn("Authentication is failed" .. key .. " plugin, code: " .. auth_code)
            end
        end
    end

    :: authenticated ::
    if status_code ~= nil then
        return 401, { message = "Authorization Failed" }
    end
end

return _M
