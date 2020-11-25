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
local local_plugins = require("apisix.plugin").plugins_hash
local stream_local_plugins = require("apisix.plugin").stream_plugins_hash
local pairs     = pairs
local ipairs    = ipairs
local pcall     = pcall
local type      = type
local table_sort = table.sort
local table_insert = table.insert
local get_uri_args = ngx.req.get_uri_args

local _M = {}


function _M.check_schema(plugins_conf, schema_type)
    for name, plugin_conf in pairs(plugins_conf) do
        core.log.info("check plugin scheme, name: ", name, ", configurations: ",
                      core.json.delay_encode(plugin_conf, true))
        if type(plugin_conf) ~= "table" then
            return false, "invalid plugin conf " ..
                core.json.encode(plugin_conf, true) ..
                " for plugin [" .. name .. "]"
        end

        local plugin_obj = local_plugins[name]
        if not plugin_obj then
            return false, "unknown plugin [" .. name .. "]"
        end

        if plugin_obj.check_schema then
            local disable = plugin_conf.disable
            plugin_conf.disable = nil

            local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
            if not ok then
                return false, "failed to check the configuration of plugin "
                              .. name .. " err: " .. err
            end

            plugin_conf.disable = disable
        end
    end

    return true
end


function _M.stream_check_schema(plugins_conf, schema_type)
    for name, plugin_conf in pairs(plugins_conf) do
        core.log.info("check stream plugin scheme, name: ", name,
                      ": ", core.json.delay_encode(plugin_conf, true))
        if type(plugin_conf) ~= "table" then
            return false, "invalid plugin conf " ..
                core.json.encode(plugin_conf, true) ..
                " for plugin [" .. name .. "]"
        end

        local plugin_obj = stream_local_plugins[name]
        if not plugin_obj then
            return false, "unknown plugin [" .. name .. "]"
        end

        if plugin_obj.check_schema then
            local disable = plugin_conf.disable
            plugin_conf.disable = nil

            local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
            if not ok then
                return false, "failed to check the configuration of "
                              .. "stream plugin [" .. name .. "]: " .. err
            end

            plugin_conf.disable = disable
        end
    end

    return true
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
