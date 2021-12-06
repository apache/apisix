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
local utils   = require("apisix.admin.utils")
local plugin  = require("apisix.plugin")
local vault   = require("apisix.core.vault")

local tab_clone = require("apisix.core.table").clone
local pairs   = pairs

local _M = {
    version = 0.1,
}


local function check_conf(username, conf)
    -- core.log.error(core.json.encode(conf))
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.consumer))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.consumer, conf)
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

    return conf.username
end


function _M.put(username, conf)
    local consumer_name, err = check_conf(username, conf)
    if not consumer_name then
        return 400, err
    end

    local key = "/consumers/" .. consumer_name
    core.log.info("key: ", key)

    -- vault-auth details gets stored into vault for security concern
    local vault_restore
    if conf.plugins and conf.plugins["vault-auth"] then
        vault_restore = tab_clone(conf.plugins["vault-auth"])

        conf.plugins["vault-auth"].secretkey = nil
        conf.plugins["vault-auth"]["fetch-vault"] = true

        -- store into vault with the path set to plugin accesskey
        local vkey = "/consumers/auth-data/" .. vault_restore.accesskey

        local vres, err = vault.set(vkey, vault_restore)
        if not vres or err then
            core.log.error("failed to store data for suffix path[", vkey,
                                    "]: into vault server, error: ", err)
            return 503, {error = err}
        end

    end
    core.log.error(core.json.delay_encode(conf, true))

    local ok, err = utils.inject_conf_with_prev_conf("consumer", key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put consumer[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    -- modify the body, some data were not stored into etcd
    if vault_restore then
        res.body.vault = {
            ["data-stored"] = vault_restore
        }
    end

    return res.status, res.body
end


function _M.get(consumer_name)
    local key = "/consumers"
    if consumer_name then
        key = key .. "/" .. consumer_name
    end

    local res, err = core.etcd.get(key, not consumer_name)
    if not res then
        core.log.error("failed to get consumer[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, consumer_name)

    if consumer_name then
        local _plugins = res.body.node.value.plugins

        if _plugins and _plugins["vault-auth"] then
            local vkey = "/consumers/auth-data/" .. _plugins["vault-auth"].accesskey

            local vres, err = vault.get(vkey)

            if not vres then
                core.log.error("failed to fetch data for suffix path[", vkey,
                                "]: into vault server, error: ", err)
                return 503, {error_msg = err}
            end

            res.body.vault = {
                ["data-fetched"] = vres
            }
        end
    end
    return res.status, res.body
end


function _M.post(consumer_name, conf)
    return 405, {error_msg = "not supported `POST` method for consumer"}
end


function _M.delete(consumer_name)
    if not consumer_name then
        return 400, {error_msg = "missing consumer name"}
    end

    local key = "/consumers/" .. consumer_name
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete consumer[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


return _M
