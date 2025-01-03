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
local plugin_name = "key-auth"
local schema_def = require("apisix.schema_def")

local schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            default = "apikey",
        },
        query = {
            type = "string",
            default = "apikey",
        },
        hide_credentials = {
            type = "boolean",
            default = false,
        },
        anonymous_consumer = schema_def.anonymous_consumer_schema,
    },
}

local consumer_schema = {
    type = "object",
    properties = {
        key = { type = "string" },
    },
    encrypt_fields = {"key"},
    required = {"key"},
}


local _M = {
    version = 0.1,
    priority = 2500,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end


local function find_consumer(ctx, conf)
    local from_header = true
    local key = core.request.header(ctx, conf.header)

    if not key then
        local uri_args = core.request.get_uri_args(ctx) or {}
        key = uri_args[conf.query]
        from_header = false
    end

    if not key then
        return nil, nil, "Missing API key in request"
    end

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return nil, nil, "Missing related consumer"
    end

    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "key")
    local consumer = consumers[key]
    if not consumer then
        return nil, nil, "Invalid API key in request"
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    if conf.hide_credentials then
        if from_header then
            core.request.set_header(ctx, conf.header, nil)
        else
            local args = core.request.get_uri_args(ctx)
            args[conf.query] = nil
            core.request.set_uri_args(ctx, args)
        end
    end

    return consumer, consumer_conf
end


function _M.rewrite(conf, ctx)
    local consumer, consumer_conf, err = find_consumer(ctx, conf)
    if not consumer then
        if not conf.anonymous_consumer then
            return 401, { message = err}
        end
        consumer, consumer_conf, err = consumer_mod.get_anonymous_consumer(conf.anonymous_consumer)
        if not consumer then
            core.log.error(err)
            return 401, { message = "Invalid user authorization"}
        end
    end

    core.log.info("consumer: ", core.json.delay_encode(consumer))
    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit key-auth rewrite")
end


return _M
