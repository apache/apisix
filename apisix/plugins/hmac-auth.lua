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
local abs        = math.abs
local ngx_time   = ngx.time
local ngx_re     = require("ngx.re")
local pairs      = pairs
local ipairs     = ipairs
local hmac_sha1  = ngx.hmac_sha1
local escape_uri = ngx.escape_uri
local core       = require("apisix.core")
local hmac       = require("resty.hmac")
local consumer   = require("apisix.consumer")
local plugin     = require("apisix.plugin")
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64

local BODY_DIGEST_KEY = "X-HMAC-DIGEST"
local SIGNATURE_KEY = "X-HMAC-SIGNATURE"
local ALGORITHM_KEY = "X-HMAC-ALGORITHM"
local DATE_KEY = "Date"
local ACCESS_KEY    = "X-HMAC-ACCESS-KEY"
local SIGNED_HEADERS_KEY = "X-HMAC-SIGNED-HEADERS"
local plugin_name   = "hmac-auth"
local MAX_REQ_BODY = 1024 * 512


local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {},
}

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        access_key = {type = "string", minLength = 1, maxLength = 256},
        secret_key = {type = "string", minLength = 1, maxLength = 256},
        algorithm = {
            type = "string",
            enum = {"hmac-sha1", "hmac-sha256", "hmac-sha512"},
            default = "hmac-sha256"
        },
        clock_skew = {
            type = "integer",
            default = 0
        },
        signed_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 50,
            }
        },
        keep_headers = {
            type = "boolean",
            title = "whether to keep the http request header",
            default = false,
        },
        encode_uri_params = {
            type = "boolean",
            title = "Whether to escape the uri parameter",
            default = true,
        },
        validate_request_body = {
            type = "boolean",
            title = "A boolean value telling the plugin to enable body validation",
            default = false,
        },
        max_req_body = {
            type = "integer",
            title = "Max request body size",
            default = MAX_REQ_BODY,
        },
    },
    encrypt_fields = {"secret_key"},
    required = {"access_key", "secret_key"},
}

local _M = {
    version = 0.1,
    priority = 2530,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema
}

local hmac_funcs = {
    ["hmac-sha1"] = function(secret_key, message)
        return hmac_sha1(secret_key, message)
    end,
    ["hmac-sha256"] = function(secret_key, message)
        return hmac:new(secret_key, hmac.ALGOS.SHA256):final(message)
    end,
    ["hmac-sha512"] = function(secret_key, message)
        return hmac:new(secret_key, hmac.ALGOS.SHA512):final(message)
    end,
}


local function array_to_map(arr)
    local map = core.table.new(0, #arr)
    for _, v in ipairs(arr) do
      map[v] = true
    end

    return map
end


local function remove_headers(ctx, ...)
    local headers = { ... }
    if headers and #headers > 0 then
        for _, header in ipairs(headers) do
            core.log.info("remove_header: ", header)
            core.request.set_header(ctx, header, nil)
        end
    end
end


function _M.check_schema(conf, schema_type)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end


local function get_consumer(access_key)
    if not access_key then
        return nil, "missing access key"
    end

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return nil, "Missing related consumer"
    end

    local consumers = consumer.consumers_kv(plugin_name, consumer_conf, "access_key")
    local consumer = consumers[access_key]
    if not consumer then
        return nil, "Invalid access key"
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    return consumer
end


local function get_conf_field(access_key, field_name)
    local consumer, err = get_consumer(access_key)
    if err then
        return false, err
    end

    return consumer.auth_conf[field_name]
end


local function do_nothing(v)
    return v
end

local function generate_signature(ctx, secret_key, params)
    local canonical_uri = ctx.var.uri
    local canonical_query_string = ""
    local request_method = core.request.get_method()
    local args = core.request.get_uri_args(ctx)

    if canonical_uri == "" then
        canonical_uri = "/"
    end

    if type(args) == "table" then
        local keys = {}
        local query_tab = {}

        for k, v in pairs(args) do
            core.table.insert(keys, k)
        end
        core.table.sort(keys)

        local field_val = get_conf_field(params.access_key, "encode_uri_params")
        core.log.info("encode_uri_params: ", field_val)

        local encode_or_not = do_nothing
        if field_val then
            encode_or_not = escape_uri
        end

        for _, key in pairs(keys) do
            local param = args[key]
            -- when args without `=<value>`, value is treated as true.
            -- In order to be compatible with args lacking `=<value>`,
            -- we need to replace true with an empty string.
            if type(param) == "boolean" then
                param = ""
            end

            -- whether to encode the uri parameters
            if type(param) == "table" then
                local vals = {}
                for _, val in pairs(param) do
                    if type(val) == "boolean" then
                        val = ""
                    end
                    core.table.insert(vals, val)
                end
                core.table.sort(vals)

                for _, val in pairs(vals) do
                    core.table.insert(query_tab, encode_or_not(key) .. "=" .. encode_or_not(val))
                end
            else
                core.table.insert(query_tab, encode_or_not(key) .. "=" .. encode_or_not(param))
            end
        end
        canonical_query_string = core.table.concat(query_tab, "&")
    end

    core.log.info("all headers: ",
                  core.json.delay_encode(core.request.headers(ctx), true))

    local signing_string_items = {
        request_method,
        canonical_uri,
        canonical_query_string,
        params.access_key,
        params.date,
    }

    if params.signed_headers then
        for _, h in ipairs(params.signed_headers) do
            local canonical_header = core.request.header(ctx, h) or ""
            core.table.insert(signing_string_items,
                              h .. ":" .. canonical_header)
            core.log.info("canonical_header name:", core.json.delay_encode(h))
            core.log.info("canonical_header value: ",
                          core.json.delay_encode(canonical_header))
        end
    end

    local signing_string = core.table.concat(signing_string_items, "\n") .. "\n"

    core.log.info("signing_string: ", signing_string,
                  " params.signed_headers:",
                  core.json.delay_encode(params.signed_headers))

    return hmac_funcs[params.algorithm](secret_key, signing_string)
end


local function validate(ctx, params)
    if not params.access_key or not params.signature then
        return nil, "access key or signature missing"
    end

    if not params.algorithm then
        return nil, "algorithm missing"
    end

    local consumer, err = get_consumer(params.access_key)
    if err then
        return nil, err
    end

    local conf = consumer.auth_conf
    if conf.algorithm ~= params.algorithm then
        return nil, "algorithm " .. params.algorithm .. " not supported"
    end

    core.log.info("clock_skew: ", conf.clock_skew)
    if conf.clock_skew and conf.clock_skew > 0 then
        local time = ngx.parse_http_time(params.date)
        core.log.info("params.date: ", params.date, " time: ", time)
        if not time then
            return nil, "Invalid GMT format time"
        end

        local diff = abs(ngx_time() - time)
        core.log.info("gmt diff: ", diff)
        if diff > conf.clock_skew then
            return nil, "Clock skew exceeded"
        end
    end

    -- validate headers
    if conf.signed_headers and #conf.signed_headers >= 1 then
        local headers_map = array_to_map(conf.signed_headers)
        if params.signed_headers then
            for _, header in ipairs(params.signed_headers) do
                if not headers_map[header] then
                    return nil, "Invalid signed header " .. header
                end
            end
        end
    end

    local secret_key          = conf and conf.secret_key
    local request_signature   = ngx_decode_base64(params.signature)
    local generated_signature = generate_signature(ctx, secret_key, params)

    core.log.info("request_signature: ", request_signature,
                  " generated_signature: ", generated_signature)

    if request_signature ~= generated_signature then
        return nil, "Invalid signature"
    end

    local validate_request_body = get_conf_field(params.access_key, "validate_request_body")
    if validate_request_body then
        local digest_header = params.body_digest
        if not digest_header then
            return nil, "Invalid digest"
        end

        local max_req_body = get_conf_field(params.access_key, "max_req_body")
        local req_body, err = core.request.get_body(max_req_body, ctx)
        if err then
            return nil, "Exceed body limit size"
        end

        req_body = req_body or ""
        local request_body_hash = ngx_encode_base64(
                hmac_funcs[params.algorithm](secret_key, req_body))
        if request_body_hash ~= digest_header then
            return nil, "Invalid digest"
        end
    end

    return consumer
end


local function get_params(ctx)
    local params = {}
    local access_key = ACCESS_KEY
    local signature_key = SIGNATURE_KEY
    local algorithm_key = ALGORITHM_KEY
    local date_key = DATE_KEY
    local signed_headers_key = SIGNED_HEADERS_KEY
    local body_digest_key = BODY_DIGEST_KEY


    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        access_key = attr.access_key or access_key
        signature_key = attr.signature_key or signature_key
        algorithm_key = attr.algorithm_key or algorithm_key
        date_key = attr.date_key or date_key
        signed_headers_key = attr.signed_headers_key or signed_headers_key
        body_digest_key = attr.body_digest_key or body_digest_key
    end

    local app_key = core.request.header(ctx, access_key)
    local signature = core.request.header(ctx, signature_key)
    local algorithm = core.request.header(ctx, algorithm_key)
    local date = core.request.header(ctx, date_key)
    local signed_headers = core.request.header(ctx, signed_headers_key)
    local body_digest = core.request.header(ctx, body_digest_key)
    core.log.info("signature_key: ", signature_key)

    -- get params from header `Authorization`
    if not app_key then
        local auth_string = core.request.header(ctx, "Authorization")
        if not auth_string then
            return params
        end

        local auth_data = ngx_re.split(auth_string, "#")
        core.log.info("auth_string: ", auth_string, " #auth_data: ",
                      #auth_data, " auth_data: ",
                      core.json.delay_encode(auth_data))

        if #auth_data == 6 and auth_data[1] == "hmac-auth-v1" then
            app_key = auth_data[2]
            signature = auth_data[3]
            algorithm = auth_data[4]
            date = auth_data[5]
            signed_headers = auth_data[6]
        end
    end

    params.access_key = app_key
    params.algorithm  = algorithm
    params.signature  = signature
    params.date  = date or ""
    params.signed_headers = signed_headers and ngx_re.split(signed_headers, ";")
    params.body_digest = body_digest

    local keep_headers = get_conf_field(params.access_key, "keep_headers")
    core.log.info("keep_headers: ", keep_headers)

    if not keep_headers then
        remove_headers(ctx, signature_key, algorithm_key, signed_headers_key)
    end

    core.log.info("params: ", core.json.delay_encode(params))

    return params
end


function _M.rewrite(conf, ctx)
    local params = get_params(ctx)
    local validated_consumer, err = validate(ctx, params)
    if not validated_consumer then
        core.log.warn("client request can't be validated: ", err or "Invalid signature")
        return 401, {message = "client request can't be validated"}
    end

    local consumer_conf = consumer.plugin(plugin_name)
    consumer.attach_consumer(ctx, validated_consumer, consumer_conf)
    core.log.info("hit hmac-auth rewrite")
end


return _M
