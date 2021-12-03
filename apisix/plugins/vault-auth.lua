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
local consumer_mod = require("apisix.consumer")
local resty_random = require("resty.random")
local hex_encode = require("resty.string").to_hex
-- local vault_fetch = require("apisix.plugins.vault.request").fetch

local ipairs   = ipairs
local plugin_name = "vault-auth"


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {},
}

local consumer_schema = {
    type = "object",
    properties = {
        accesskey = {type = "string"},
        secretkey = {type = "string"}
    }
}

local metadata_schema = {
    type = "object",
    properties = {
        host = {type = "string", default = "127.0.0.1"},
        port = {type = "integer", default = 8200},
        vault_token = {type = "string"},
        vault_kv_path = {type = "string", default = "kv/apisix/plugins/vault-auth"}
    }
}

local _M = {
    version = 0.1,
    priority = 2535,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
    metadata_schema = metadata_schema,
}


local create_consume_cache
do
    local consumer_names = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_names[consumer.auth_conf.accesskey] = consumer
        end

        return consumer_names
    end

end -- do


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        local ok, err = core.schema.check(consumer_schema, conf)
        if not ok then
            return false, err
        end

    elseif schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    else
        return core.schema.check(schema, conf)
    end

    if not conf.accesskey then
        conf.accesskey = hex_encode(resty_random.bytes(16, true))
    end
    if not conf.secretkey then
        conf.secretkey = hex_encode(resty_random.bytes(16, true))
    end

    return true
end


function _M.rewrite(conf, ctx)
    local uri_args = core.request.get_uri_args(ctx) or {}
    local headers = core.request.headers(ctx) or {}

    local accesskey = headers.accesskey or uri_args.accesskey
    local secretkey = headers.secretkey or uri_args.secretkey

    if not accesskey then
        return 401, {message = "Missing accesskey and secretkey found in request"}
    end

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
        create_consume_cache, consumer_conf)

    local consumer = consumers[accesskey]
    if not consumer then
        return 401, {message = "Invalid accesskey attached with the request"}
    end

    core.log.error(core.json.delay_encode(consumer, true))
    core.log.error("sec ", secretkey)

    if consumer.auth_conf.secretkey ~= secretkey then
        return 401, {message = "Invalid secretkey attached with the request"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit vault-auth rewrite")
end


return _M
