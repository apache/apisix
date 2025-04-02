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
local core     = require("apisix.core")
local plugins  = require("apisix.admin.plugins")
local plugin   = require("apisix.plugin")
local resource = require("apisix.admin.resource")
local consumer = require("apisix.consumer")
local utils = require("apisix.admin.utils")
local pairs    = pairs

local function check_duplicate_key(id, plugins)
    for name, plugin_conf in pairs(plugins) do
        local plugin_obj = plugin.get(name)
        if not plugin_obj then
            goto continue
        end

        if plugin_obj.type ~= "auth" then
            goto continue
        end

        local key_field = utils.plugin_key_map[name]
        if not key_field then
            goto continue
        end

        local key_value = plugin_conf[key_field]
        if not key_value then
            goto continue
        end

        local consumer = consumer.find_consumer(name, key_field, key_value)
        if consumer and consumer.credential_id ~= id then
            return nil, "duplicate key found with consumer: " .. consumer.username
        end

        ::continue::
    end

    return true
end

local function check_conf(id, conf, _need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if conf.plugins then
        local ok, err = check_duplicate_key(id, conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end

        ok, err = plugins.check_schema(conf.plugins, core.schema.TYPE_CONSUMER)
        if not ok then
            return nil, {error_msg = "invalid plugins configuration: " .. err}
        end

        for name, _ in pairs(conf.plugins) do
            local plugin_obj = plugin.get(name)
            if not plugin_obj then
                return nil, {error_msg = "unknown plugin " .. name}
            end
            if plugin_obj.type ~= "auth" then
                return nil, {error_msg = "only supports auth type plugins in consumer credential"}
            end
        end
    end

    return true, nil
end

-- get_credential_etcd_key is used to splice the credential's etcd key (without prefix)
-- from credential_id and sub_path.
-- Parameter credential_id is from the uri or payload; sub_path is in the form of
-- {consumer_name}/credentials or {consumer_name}/credentials/{credential_id}.
-- Only if GET credentials list, credential_id is nil, sub_path is like {consumer_name}/credentials,
-- so return value is /consumers/{consumer_name}/credentials.
-- In the other methods, credential_id is not nil, return value is
-- /consumers/{consumer_name}/credentials/{credential_id}.
local function get_credential_etcd_key(credential_id, _conf, sub_path, _args)
    if credential_id then
        local uri_segs = core.utils.split_uri(sub_path)
        local consumer_name = uri_segs[1]
        return "/consumers/" .. consumer_name .. "/credentials/" .. credential_id
    end

    return "/consumers/" .. sub_path
end

return resource.new({
    name = "credentials",
    kind = "credential",
    schema = core.schema.credential,
    checker = check_conf,
    get_resource_etcd_key = get_credential_etcd_key,
    unsupported_methods = {"post", "patch"}
})
