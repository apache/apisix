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
local ngx        = ngx
local type       = type
local select     = select
local str_fmt    = string.format
local ngx_req    = ngx.req
local pairs      = pairs
local ipairs     = ipairs
local hmac_sha1  = ngx.hmac_sha1
local escape_uri = ngx.escape_uri
local core       = require("apisix.core")
local hmac       = require("resty.hmac")
local consumer   = require("apisix.consumer")
local ngx_decode_base64 = ngx.decode_base64
local SIGNATURE_KEY = "X-HMAC-SIGNATURE"
local ALGORITHM_KEY = "X-HMAC-ALGORITHM"
local TIMESTAMP_KEY = "X-HMAC-TIMESTAMP"
local ACCESS_KEY    = "X-HMAC-ACCESS-KEY"
local plugin_name   = "hmac-auth"

local schema = {
    type = "object",
    properties = {
        access_key = {type = "string"},
        secret_key = {type = "string"},
        algorithm = {
            type = "string",
            enum = {"hmac-sha1", "hmac-sha256", "hmac-sha512"},
            default = "hmac-sha256"
        }
    }
}

local _M = {
    version = 0.1,
    priority = 2530,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}

local hmac_funcs = {
    ["hmac-sha1"] = function(secret, message)
        return hmac_sha1(secret, message)
    end,
    ["hmac-sha256"] = function(secret, message)
        return hmac:new(secret, hmac.ALGOS.SHA256):final(message)
    end,
    ["hmac-sha512"] = function(secret, message)
        return hmac:new(secret, hmac.ALGOS.SHA512):final(message)
    end,
}


local function try_attr(t, ...)
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        t = t[attr]
        if type(t) ~= "table" then
            return false
        end
    end

    return true
end


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_ids)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_ids[consumer.auth_conf.access_key] = consumer
        end

        return consumer_ids
    end

end -- do


function _M.check_schema(conf)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function get_secret(access_key)
    if not access_key then
        return nil, nil, {message = "missing access key"}
    end

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return nil, nil, {message = "Missing related consumer"}
    end

    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    local consumer = consumers[access_key]
    if not consumer then
        return nil, nil, {message = "Invalid access key"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local secret = consumer.auth_conf and consumer.auth_conf.secret

    return secret, consumer, nil
end


local function generate_signature(ctx, secret_key, params)
    --local canonical_uri = ctx.var.uri
    local canonical_query_string = ""
    --local request_method = ngx_req.get_method()
    local args = ngx_req.get_uri_args()

    if type(args) == "table" then
        local keys = {}
        local query_tab = {}
        local query_tab_size = 1

        for k,v in pairs(args) do
            core.table.insert(keys, k)
        end
        core.table.sort(keys)

        for _, key in pairs(keys) do
            local param = args[key]
            if type(param) == "table" then
                for _, vval in pairs(param) do
                    query_tab[query_tab_size] = escape_uri(key) .. "=" .. escape_uri(vval)
                    query_tab_size = query_tab_size + 1
                end
            else
                query_tab[query_tab_size] = escape_uri(key) .. "=" .. escape_uri(param)
                query_tab_size = query_tab_size + 1
            end
        end
        canonical_query_string = core.table.concat(query_tab, "&")
    end

    local signing_string = canonical_query_string .. params.ak ..
        params.timestamp .. params.secret_key

    return hmac_funcs[params.algorithm](secret_key, signing_string)
end


local function validate_signature(ctx, params)
    local local_conf = core.config.local_conf()
    local access_key = ACCESS_KEY

    if try_attr(local_conf, "plugin_attr", "hmac-auth") then
        local attr = local_conf.plugin_attr["hmac-auth"]
        access_key = attr.access_key or access_key
    end

    local akey = core.request.header(ctx, access_key)
    local secret_key, consumer, err = get_secret(akey)
    if err then
        return false, nil, err
    end

    local request_signature = ngx_decode_base64(params.signature)
    local generated_signature = generate_signature(ctx, secret_key, params)

    return request_signature == generated_signature, consumer
end

local function get_params(ctx)
    local params = {}
    local local_conf = core.config.local_conf()
    local signature_key = SIGNATURE_KEY
    local algorithm_key = ALGORITHM_KEY
    local timestamp_key = TIMESTAMP_KEY
    local access_key = ACCESS_KEY

    if try_attr(local_conf, "plugin_attr", "hmac-auth") then
        local attr = local_conf.plugin_attr["hmac-auth"]
        signature_key = attr.signature_key or signature_key
        algorithm_key = attr.algorithm_key or algorithm_key
        timestamp_key = attr.timestamp_key or timestamp_key
        access_key = attr.access_key or access_key
    end

    local ak = core.request.header(ctx, access_key)
    local signature = core.request.header(ctx, signature_key)
    local algorithm = core.request.header(ctx, algorithm_key)
    local timestamp = core.request.header(ctx, timestamp_key)

    params.ak = ak
    params.algorithm = algorithm
    params.signature = signature
    params.timestamp = timestamp

    return params
end


local function validate_params(params, conf)
    if not params.ak and params.signature then
      return false, {message = "access key or signature missing"}
    end

    if conf.algorithm ~= params.algorithm then
        return false, {message = str_fmt("algorithm %s not supported", params.algorithm)}
    end

    return true
end


function _M.rewrite(conf, ctx)
    local params = get_params(ctx)
    local ok, err = validate_params(params)
    if not ok then
        return 401, err
    end

    local ok, consumer, err = validate_signature(ctx, params)
    if not ok then
        return 401, err
    end

    ctx.consumer = consumer
    ctx.consumer_id = consumer.consumer_id
    ctx.consumer_ver = conf.conf_version
    core.log.info("hit jwt-auth rewrite")
end


return _M
