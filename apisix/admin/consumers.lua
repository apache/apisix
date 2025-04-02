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
local core    = require("apisix.core")
local plugins = require("apisix.admin.plugins")
local resource = require("apisix.admin.resource")
local plugin = require("apisix.plugin")
local pairs = pairs
local consumer = require("apisix.consumer")
local utils = require("apisix.admin.utils")


local function check_duplicate_key(username, plugins_conf)
    if not plugins_conf then
        return true
    end

    for plugin_name, plugin_conf in pairs(plugins_conf) do
        local plugin_obj = plugin.get(plugin_name)
        if not plugin_obj then
            return nil, "unknown plugin " .. plugin_name
        end

        if plugin_obj.type ~= "auth" then
            goto continue
        end

        local key_field = utils.plugin_key_map[plugin_name]
        if not key_field then
            goto continue
        end

        local key_value = plugin_conf[key_field]
        if not key_value then
            goto continue
        end

        local consumer = consumer.find_consumer(plugin_name, key_field, key_value)
        if consumer and consumer.username ~= username then
            return nil, "duplicate key found with consumer: " .. consumer.username
        end

        ::continue::
    end

    return true
end

local function check_conf(username, conf, need_username, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if username and username ~= conf.username then
        return nil, {error_msg = "wrong username" }
    end

    if conf.plugins then
      local ok, err = check_duplicate_key(conf.username, conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end

        ok, err = plugins.check_schema(conf.plugins, core.schema.TYPE_CONSUMER)
        if not ok then
            return nil, {error_msg = "invalid plugins configuration: " .. err}
        end
    end

    if conf.group_id then
        local key = "/consumer_groups/" .. conf.group_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch consumer group info by "
                                     .. "consumer group id [" .. conf.group_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch consumer group info by "
                                     .. "consumer group id [" .. conf.group_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    return conf.username
end


return resource.new({
    name = "consumers",
    kind = "consumer",
    schema = core.schema.consumer,
    checker = check_conf,
    unsupported_methods = {"post", "patch"}
})
