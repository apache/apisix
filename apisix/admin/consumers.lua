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

local function check_conf(username, conf, need_username, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if username and username ~= conf.username then
        return nil, {error_msg = "wrong username" }
    end

    if conf.plugins then
        ok, err = plugins.check_schema(conf.plugins, core.schema.TYPE_CONSUMER)
        if not ok then
            return nil, {
                error_msg = "invalid plugins configuration: " .. err
            }
        end

        -- check duplicate key
        for plugin_name, plugin_conf in pairs(conf.plugins or {}) do
            local plugin_obj = plugin.get(plugin_name)
            if not plugin_obj then
                return nil, {error_msg = "unknown plugin " .. plugin_name}
            end
            if plugin_obj.type == "auth" then
                local decrypted_conf = core.table.deepcopy(plugin_conf)
                plugin.decrypt_conf(plugin_name, decrypted_conf, core.schema.TYPE_CONSUMER)

                local plugin_key_map = {
                    ["key-auth"] = "key",
                    ["basic-auth"] = "username",
                    ["jwt-auth"] = "key",
                    ["hmac-auth"] = "key_id"
                }

                local key_field = plugin_key_map[plugin_name]
                if key_field then
                    local key_value = decrypted_conf[key_field]
                    if key_value then
                        local consumer, _ = require("apisix.consumer")
                            .find_consumer(plugin_name, key_field, key_value)
                        if consumer and consumer.username ~= conf.username then
                            return nil, {
                                error_msg = "duplicate key found with consumer: " 
                                    .. consumer.username
                            }
                        end
                    end
                end
            end
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
