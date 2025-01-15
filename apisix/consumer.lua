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
local core           = require("apisix.core")
local config_local   = require("apisix.core.config_local")
local secret         = require("apisix.secret")
local plugin         = require("apisix.plugin")
local plugin_checker = require("apisix.plugin").plugin_checker
local check_schema   = require("apisix.core.schema").check
local error          = error
local ipairs         = ipairs
local pairs          = pairs
local type           = type
local string_sub     = string.sub
local consumers


local _M = {
    version = 0.3,
}

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local function remove_etcd_prefix(key)
    local prefix = ""
    local local_conf = config_local.local_conf()
    if local_conf.etcd and local_conf.etcd.prefix then
        prefix = local_conf.etcd.prefix
    end
    return string_sub(key, #prefix + 1)
end

-- /{etcd.prefix}/consumers/{consumer_name}/credentials/{credential_id} --> {consumer_name}
local function get_consumer_name_from_credential_etcd_key(key)
    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[3]
end

local function is_credential_etcd_key(key)
    if not key then
        return false
    end

    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[2] == "consumers" and uri_segs[4] == "credentials"
end

local function get_credential_id_from_etcd_key(key)
    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[5]
end

local function filter_consumers_list(data_list)
    if #data_list == 0 then
        return data_list
    end

    local list = {}
    for _, item in ipairs(data_list) do
        if not (type(item) == "table" and is_credential_etcd_key(item.key)) then
            core.table.insert(list, item)
        end
    end

    return list
end

local function plugin_consumer()
    local plugins = {}

    if consumers.values == nil then
        return plugins
    end

    -- consumers.values is the list that got from etcd by prefix key {etcd_prefix}/consumers.
    -- So it contains consumers and credentials.
    -- The val in the for-loop may be a Consumer or a Credential.
    for _, val in ipairs(consumers.values) do
        if type(val) ~= "table" then
            goto CONTINUE
        end

        for name, config in pairs(val.value.plugins or {}) do
            local plugin_obj = plugin.get(name)
            if plugin_obj and plugin_obj.type == "auth" then
                if not plugins[name] then
                    plugins[name] = {
                        nodes = {},
                        conf_version = consumers.conf_version
                    }
                end

                -- if the val is a Consumer, clone it to the local consumer;
                -- if the val is a Credential, to get the Consumer by consumer_name and then clone
                -- it to the local consumer.
                local consumer
                if is_credential_etcd_key(val.key) then
                    local consumer_name = get_consumer_name_from_credential_etcd_key(val.key)
                    local the_consumer = consumers:get(consumer_name)
                    if the_consumer and the_consumer.value then
                        consumer = core.table.clone(the_consumer.value)
                        consumer.modifiedIndex = the_consumer.modifiedIndex
                        consumer.credential_id = get_credential_id_from_etcd_key(val.key)
                    else
                        -- Normally wouldn't get here:
                        -- it should belong to a consumer for any credential.
                        core.log.error("failed to get the consumer for the credential,",
                            " a wild credential has appeared!",
                            " credential key: ", val.key, ", consumer name: ", consumer_name)
                        goto CONTINUE
                    end
                else
                    consumer = core.table.clone(val.value)
                    consumer.modifiedIndex = val.modifiedIndex
                end

                -- if the consumer has labels, set the field custom_id to it.
                -- the custom_id is used to set in the request headers to the upstream.
                if consumer.labels then
                    consumer.custom_id = consumer.labels["custom_id"]
                end

                -- Note: the id here is the key of consumer data, which
                -- is 'username' field in admin
                consumer.consumer_name = consumer.id
                consumer.auth_conf = config
                core.log.info("consumer:", core.json.delay_encode(consumer))
                core.table.insert(plugins[name].nodes, consumer)
            end
        end

        ::CONTINUE::
    end

    return plugins
end

_M.filter_consumers_list = filter_consumers_list

function _M.get_consumer_key_from_credential_key(key)
    local uri_segs = core.utils.split_uri(key)
    return "/consumers/" .. uri_segs[3]
end

function _M.plugin(plugin_name)
    local plugin_conf = core.lrucache.global("/consumers",
                            consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


-- attach chosen consumer to the ctx, used in auth plugin
function _M.attach_consumer(ctx, consumer, conf)
    ctx.consumer = consumer
    ctx.consumer_name = consumer.consumer_name
    ctx.consumer_group_id = consumer.group_id
    ctx.consumer_ver = conf.conf_version

    core.request.set_header(ctx, "X-Consumer-Username", consumer.username)
    core.request.set_header(ctx, "X-Credential-Identifier", consumer.credential_id)
    core.request.set_header(ctx, "X-Consumer-Custom-ID", consumer.custom_id)
end


function _M.consumers()
    if not consumers then
        return nil, nil
    end

    return filter_consumers_list(consumers.values), consumers.conf_version
end


local function create_consume_cache(consumers_conf, key_attr)
    local consumer_names = {}

    for _, consumer in ipairs(consumers_conf.nodes) do
        core.log.info("consumer node: ", core.json.delay_encode(consumer))
        local new_consumer = core.table.clone(consumer)
        new_consumer.auth_conf = secret.fetch_secrets(new_consumer.auth_conf, true,
                                                        new_consumer.auth_conf, "")
        consumer_names[new_consumer.auth_conf[key_attr]] = new_consumer
    end

    return consumer_names
end


function _M.consumers_kv(plugin_name, consumer_conf, key_attr)
    local consumers = lrucache("consumers_key#" .. plugin_name, consumer_conf.conf_version,
        create_consume_cache, consumer_conf, key_attr)

    return consumers
end

local function check_consumer(consumer, key)
    local data_valid
    local err
    if is_credential_etcd_key(key) then
        data_valid, err = check_schema(core.schema.credential, consumer)
    else
        data_valid, err = check_schema(core.schema.consumer, consumer)
    end
    if not data_valid then
        return data_valid, err
    end

    return plugin_checker(consumer, core.schema.TYPE_CONSUMER)
end


local function filter(consumer)
    if not consumer.value then
        return
    end

    -- We expect the id is the same as username. Fix up it here if it isn't.
    consumer.value.id = consumer.value.username
end


function _M.init_worker()
    local err
    local cfg = {
        automatic = true,
        checker = check_consumer,
    }
    if core.config.type ~= "etcd" then
        cfg.filter = filter
    end

    consumers, err = core.config.new("/consumers", cfg)
    if not consumers then
        error("failed to create etcd instance for fetching consumers: " .. err)
        return
    end
end


return _M
