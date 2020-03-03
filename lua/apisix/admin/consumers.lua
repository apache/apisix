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
local plugin  = require("apisix.plugin")
local pairs   = pairs

local _M = {
    version = 0.1,
}


local function check_conf(consumer_name, conf)
    -- core.log.error(core.json.encode(conf))
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    local consumer_name = conf.username or consumer_name
    if not consumer_name then
        return nil, {error_msg = "missing consumer name"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.consumer))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.consumer, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if conf.plugins then
        ok, err = plugins.check_schema(conf.plugins)
        if not ok then
            return nil, {error_msg = "invalid plugins configuration: " .. err}
        end

        local count_auth_plugin = 0
        for name, conf in pairs(conf.plugins) do
            local plugin_obj = plugin.get(name)
            if plugin_obj.type == 'auth' then
                count_auth_plugin = count_auth_plugin + 1
                if count_auth_plugin > 1 then
                    return nil, {error_msg = "only one auth plugin is allowed"}
                end
            end
        end

        if count_auth_plugin == 0 then
            return nil, {error_msg = "require one auth plugin"}
        end
    end

    return consumer_name
end


function _M.put(consumer_name, conf)
    local consumer_name, err = check_conf(consumer_name, conf)
    if not consumer_name then
        return 400, err
    end

    local key = "/consumers/" .. consumer_name
    core.log.info("key: ", key)
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put consumer[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(consumer_name)
    local key = "/consumers"
    if consumer_name then
        key = key .. "/" .. consumer_name
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get consumer[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(consumer_name, conf)
    return 400, {error_msg = "not support `POST` method for consumer"}
end


function _M.delete(consumer_name)
    if not consumer_name then
        return 400, {error_msg = "missing consumer name"}
    end

    local key = "/consumers/" .. consumer_name
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete consumer[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
