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
local core = require("apisix.core")
local check_schema = require("apisix.plugin").check_schema
local stream_check_schema = require("apisix.plugin").stream_check_schema
local ipairs    = ipairs
local pcall     = pcall
local table_sort = table.sort
local table_insert = table.insert
local get_uri_args = ngx.req.get_uri_args

local _M = {}


function _M.check_schema(plugins_conf, schema_type)
    return check_schema(plugins_conf, schema_type, false)
end


function _M.stream_check_schema(plugins_conf, schema_type)
    return stream_check_schema(plugins_conf, schema_type, false)
end


function _M.get(name)
    if not name then
        return 400, {error_msg = "not found plugin name"}
    end

    local plugin_name = "apisix.plugins." .. name

    local ok, plugin = pcall(require, plugin_name)
    if not ok then
        core.log.warn("failed to load plugin [", name, "] err: ", plugin)
        return 400, {error_msg = "failed to load plugin " .. name}
    end

    local arg = get_uri_args()
    local json_schema = plugin.schema
    if arg and arg["schema_type"] == "consumer" then
        json_schema = plugin.consumer_schema
    end

    if not json_schema then
        return 400, {error_msg = "not found schema"}
    end

    return 200, json_schema
end


function _M.get_plugins_list()
    local plugins = core.config.local_conf().plugins
    local priorities = {}
    local success = {}
    for i, name in ipairs(plugins) do
        local plugin_name = "apisix.plugins." .. name
        local ok, plugin = pcall(require, plugin_name)
        if ok and plugin.priority then
            priorities[name] = plugin.priority
            table_insert(success, name)
        end
    end

    local function cmp(x, y)
        return priorities[x] > priorities[y]
    end

    table_sort(success, cmp)
    return success
end


return _M
