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
local require = require
local pairs = pairs

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        auth_plugins = { type = "array", minItems = 2 }
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
        for auth_plugin_name, auth_plugin_conf in pairs(auth_plugin) do
            local auth = require("apisix.plugins." .. auth_plugin_name)
            if auth == nil then
                return false, auth_plugin_name .. " plugin did not found"
            else
                if auth.type ~= 'auth' then
                    return false, auth_plugin_name .. " plugin is not supported"
                end
                local ok, err = auth.check_schema(auth_plugin_conf, auth.schema)
                if not ok then
                    return false, "plugin " .. auth_plugin_name .. " check schema failed: " .. err
                end
            end
        end
    end

    return true
end

function _M.rewrite(conf, ctx)
    local auth_plugins = conf.auth_plugins
    local status_code
    local errors = {}

    for k, auth_plugin in pairs(auth_plugins) do
        for auth_plugin_name, auth_plugin_conf in pairs(auth_plugin) do
            local auth = require("apisix.plugins." .. auth_plugin_name)
            -- returns 401 HTTP status code if authentication failed, otherwise returns nothing.
            local auth_code, err = auth.rewrite(auth_plugin_conf, ctx)
            if type(err) == "table" then
                err = err.message  -- compat
            end

            status_code = auth_code
            if auth_code == nil then
                core.log.debug(auth_plugin_name .. " succeed to authenticate the request")
                goto authenticated
            else
                core.table.insert(errors, auth_plugin_name ..
                        " failed to authenticate the request, code: "
                        .. auth_code .. ". error: " .. err)
            end
        end
    end

    :: authenticated ::
    if status_code ~= nil then
        for _, error in ipairs(errors) do
            core.log.warn(error)
        end
        return 401, { message = "Authorization Failed" }
    end
end

return _M
