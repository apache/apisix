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
local core            = require("apisix.core")
local consumer_mod    = require("apisix.consumer")
local base64          = require("ngx.base64")
local ngx             = ngx
local sub_str         = string.sub
local cipher          = require("resty.openssl.cipher").new("aes-256-gcm")

local plugin_name     = "jwe-decrypt"

local schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            default = "Authorization"
        },
        forward_header = {
            type = "string",
            default = "Authorization"
        },
        strict = {
            type = "boolean",
            default = true
        }
    },
    required = { "header", "forward_header" },
}

local consumer_schema = {
    type = "object",
    properties = {
        key = { type = "string" },
        secret = { type = "string", minLength = 32 },
         is_base64_encoded = { type = "boolean" },
    },
    required = { "key", "secret" },
}


local _M = {
    version = 0.1,
    priority = 2509,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function get_secret(conf)
    local secret = conf.secret

    if conf. is_base64_encoded then
        return base64.decode_base64(secret)
    end

    return secret
end


local function load_jwe_token(jwe_token)
    local o = { valid = false }
    o.header, o.enckey, o.iv, o.ciphertext, o.tag = jwe_token:match("(.-)%.(.-)%.(.-)%.(.-)%.(.*)")
    if not o.header then
        return o
    end
    local he = base64.decode_base64url(o.header)
    if not he then
        return o
    end
    o.header_obj = core.json.decode(he)
    if not o.header_obj then
        return o
    end
    o.valid = true
    return o
end


local function jwe_decrypt_with_obj(o, consumer)
    local secret = get_secret(consumer.auth_conf)
    local dec = base64.decode_base64url
    return cipher:decrypt(secret, dec(o.iv), dec(o.ciphertext), false, o.header, dec(o.tag))
end


local function jwe_encrypt(o, consumer)
    local secret = get_secret(consumer.auth_conf)
    local enc = base64.encode_base64url
    o.ciphertext = cipher:encrypt(secret, o.iv, o.plaintext, false, o.header)
    o.tag = cipher:get_aead_tag()
    return o.header .. ".." .. enc(o.iv) .. "." .. enc(o.ciphertext) .. "." .. enc(o.tag)
end


local function get_consumer(key)
    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return nil
    end
    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "key")
    if not consumers then
        return nil
    end
    core.log.info("consumers: ", core.json.delay_encode(consumers))
    return consumers[key]
end


local function fetch_jwe_token(conf, ctx)
    local token = core.request.header(ctx, conf.header)
    if token then
        local prefix = sub_str(token, 1, 7)
        if prefix == 'Bearer ' or prefix == 'bearer ' then
            return sub_str(token, 8)
        end

        return token
    end
end


function _M.rewrite(conf, ctx)
    -- fetch token and hide credentials if necessary
    local jwe_token, err = fetch_jwe_token(conf, ctx)
    if not jwe_token and conf.strict then
        core.log.info("failed to fetch JWE token: ", err)
        return 403, { message = "missing JWE token in request" }
    end

    local jwe_obj = load_jwe_token(jwe_token)
    if not jwe_obj.valid then
        return 400, { message = "JWE token invalid" }
    end

    if not jwe_obj.header_obj.kid then
        return 400, { message = "missing kid in JWE token" }
    end

    local consumer = get_consumer(jwe_obj.header_obj.kid)
    if not consumer then
        return 400, { message = "invalid kid in JWE token" }
    end

    local plaintext, err = jwe_decrypt_with_obj(jwe_obj, consumer)
    if err ~= nil then
        return 400, { message = "failed to decrypt JWE token" }
    end
    core.request.set_header(ctx, conf.forward_header, plaintext)
end


local function gen_token()
    local args = core.request.get_uri_args()
    if not args or not args.key then
        return core.response.exit(400)
    end

    local key = args.key
    local payload = args.payload
    if payload then
        payload = ngx.unescape_uri(payload)
    end

    local consumer = get_consumer(key)
    if not consumer then
        return core.response.exit(404)
    end

    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local iv = args.iv
    if not iv then
        -- TODO: random bytes
        iv = "123456789012"
    end

    local obj = {
        iv = iv,
        plaintext = payload,
        header_obj = {
            kid = key,
            alg = "dir",
            enc = "A256GCM",
        },
    }
    obj.header = base64.encode_base64url(core.json.encode(obj.header_obj))
    local jwe_token = jwe_encrypt(obj, consumer)
    if jwe_token then
        return core.response.exit(200, jwe_token)
    end

    return core.response.exit(404)
end


function _M.api()
    return {
        {
            methods = { "GET" },
            uri = "/apisix/plugin/jwe/encrypt",
            handler = gen_token,
        }
    }
end

return _M
