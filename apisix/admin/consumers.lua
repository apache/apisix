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
local plugin  = require("apisix.plugin")
local pairs   = pairs


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
            return nil, {error_msg = "invalid plugins configuration: " .. err}
        end

        local count_auth_plugin = 0
        for name, conf in pairs(conf.plugins) do
            local plugin_obj = plugin.get(name)
            if plugin_obj.type == 'auth' then
                count_auth_plugin = count_auth_plugin + 1
            end
        end

        if count_auth_plugin == 0 then
            return nil, {error_msg = "require one auth plugin"}
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
