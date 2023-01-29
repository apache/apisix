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
local jwt      = require("resty.jwt")
local consumer_mod = require("apisix.consumer")
local resty_random = require("resty.random")
local new_tab = require ("table.new")

local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ngx      = ngx
local ngx_time = ngx.time
local sub_str  = string.sub
local table_insert = table.insert
local table_concat = table.concat
local ngx_re_gmatch = ngx.re.gmatch
local plugin_name = "jwt-auth"
local pcall = pcall


local schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            default = "authorization"
        },
        query = {
            type = "string",
            default = "jwt"
        },
        cookie = {
            type = "string",
            default = "jwt"
        },
        hide_credentials = {
            type = "boolean",
            default = false
        }
    },
}

local consumer_schema = {
    type = "object",
    -- can't use additionalProperties with dependencies
    properties = {
        key = {type = "string"},
        secret = {type = "string"},
        algorithm = {
            type = "string",
            enum = {"HS256", "HS512", "RS256", "ES256"},
            default = "HS256"
        },
        exp = {type = "integer", minimum = 1, default = 86400},
        base64_secret = {
            type = "boolean",
            default = false
        },
        lifetime_grace_period = {
            type = "integer",
            minimum = 0,
            default = 0
        }
    },
    dependencies = {
        algorithm = {
            oneOf = {
                {
                    properties = {
                        algorithm = {
                            enum = {"HS256", "HS512"},
                            default = "HS256"
                        },
                    },
                },
                {
                    properties = {
                        public_key = {type = "string"},
                        private_key= {type = "string"},
                        algorithm = {
                            enum = {"RS256", "ES256"},
                        },
                    },
                    required = {"public_key", "private_key"},
                },
            }
        }
    },
    encrypt_fields = {"secret", "private_key"},
    required = {"key"},
}


local _M = {
    version = 0.1,
    priority = 2510,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema
}


function _M.check_schema(conf, schema_type)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    local ok, err
    if schema_type == core.schema.TYPE_CONSUMER then
        ok, err = core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end

    if not ok then
        return false, err
    end

    if conf.algorithm ~= "RS256" and conf.algorithm ~= "ES256" and not conf.secret then
        conf.secret = ngx_encode_base64(resty_random.bytes(32, true))
    elseif conf.base64_secret then
        if ngx_decode_base64(conf.secret) == nil then
            return false, "base64_secret required but the secret is not in base64 format"
        end
    end

    if conf.algorithm == "RS256" or conf.algorithm == "ES256" then
        -- Possible options are a) public key is missing
        -- b) private key is missing
        if not conf.public_key then
            return false, "missing valid public key"
        end
        if not conf.private_key then
            return false, "missing valid private key"
        end
    end

    return true
end

local function remove_specified_cookie(src, key)
    local cookie_key_pattern = "([a-zA-Z0-9-_]*)"
    local cookie_val_pattern = "([a-zA-Z0-9-._]*)"
    local t = new_tab(1, 0)

    local it, err = ngx_re_gmatch(src, cookie_key_pattern .. "=" .. cookie_val_pattern, "jo")
    if not it then
        core.log.error("match origins failed: ", err)
        return src
    end
    while true do
        local m, err = it()
        if err then
            core.log.error("iterate origins failed: ", err)
            return src
        end
        if not m then
            break
        end
        if m[1] ~= key then
            table_insert(t, m[0])
        end
    end

    return table_concat(t, "; ")
end

local function fetch_jwt_token(conf, ctx)
    local token = core.request.header(ctx, conf.header)
    if token then
        if conf.hide_credentials then
            -- hide for header
            core.request.set_header(ctx, conf.header, nil)
        end

        local prefix = sub_str(token, 1, 7)
        if prefix == 'Bearer ' or prefix == 'bearer ' then
            return sub_str(token, 8)
        end

        return token
    end

    local uri_args = core.request.get_uri_args(ctx) or {}
    token = uri_args[conf.query]
    if token then
        if conf.hide_credentials then
            -- hide for query
            uri_args[conf.query] = nil
            core.request.set_uri_args(ctx, uri_args)
        end
        return token
    end

    local val = ctx.var["cookie_" .. conf.cookie]
    if not val then
        return nil, "JWT not found in cookie"
    end

    if conf.hide_credentials then
        -- hide for cookie
        local src = core.request.header(ctx, "Cookie")
        local reset_val = remove_specified_cookie(src, conf.cookie)
        core.request.set_header(ctx, "Cookie", reset_val)
    end

    return val
end

local function get_secret(conf, consumer_name)
    local secret = conf.secret

    if conf.base64_secret then
        return ngx_decode_base64(secret)
    end

    return secret
end


local function get_rsa_or_ecdsa_keypair(conf, consumer_name)
    local public_key = conf.public_key
    local private_key = conf.private_key

    if public_key and private_key then
        return public_key, private_key
    elseif public_key and not private_key then
        return nil, nil, "missing private key"
    elseif not public_key and private_key then
        return nil, nil, "missing public key"
    else
        return nil, nil, "public and private keys are missing"
    end
end


local function get_real_payload(key, auth_conf, payload)
    local real_payload = {
        key = key,
        exp = ngx_time() + auth_conf.exp
    }
    if payload then
        local extra_payload = core.json.decode(payload)
        core.table.merge(real_payload, extra_payload)
    end
    return real_payload
end


local function sign_jwt_with_HS(key, consumer, payload)
    local auth_secret, err = get_secret(consumer.auth_conf, consumer.username)
    if not auth_secret then
        core.log.error("failed to sign jwt, err: ", err)
        core.response.exit(503, "failed to sign jwt")
    end
    local ok, jwt_token = pcall(jwt.sign, _M,
        auth_secret,
        {
            header = {
                typ = "JWT",
                alg = consumer.auth_conf.algorithm
            },
            payload = get_real_payload(key, consumer.auth_conf, payload)
        }
    )
    if not ok then
        core.log.warn("failed to sign jwt, err: ", jwt_token.reason)
        core.response.exit(500, "failed to sign jwt")
    end
    return jwt_token
end


local function sign_jwt_with_RS256_ES256(key, consumer, payload)
    local public_key, private_key, err = get_rsa_or_ecdsa_keypair(
        consumer.auth_conf, consumer.username
    )
    if not public_key then
        core.log.error("failed to sign jwt, err: ", err)
        core.response.exit(503, "failed to sign jwt")
    end

    local ok, jwt_token = pcall(jwt.sign, _M,
        private_key,
        {
            header = {
                typ = "JWT",
                alg = consumer.auth_conf.algorithm,
                x5c = {
                    public_key,
                }
            },
            payload = get_real_payload(key, consumer.auth_conf, payload)
        }
    )
    if not ok then
        core.log.warn("failed to sign jwt, err: ", jwt_token.reason)
        core.response.exit(500, "failed to sign jwt")
    end
    return jwt_token
end

-- introducing method_only flag (returns respective signing method) to save http API calls.
local function algorithm_handler(consumer, method_only)
    if not consumer.auth_conf.algorithm or consumer.auth_conf.algorithm == "HS256"
            or consumer.auth_conf.algorithm == "HS512" then
        if method_only then
            return sign_jwt_with_HS
        end

        return get_secret(consumer.auth_conf, consumer.username)
    elseif consumer.auth_conf.algorithm == "RS256" or consumer.auth_conf.algorithm == "ES256"  then
        if method_only then
            return sign_jwt_with_RS256_ES256
        end

        local public_key, _, err = get_rsa_or_ecdsa_keypair(consumer.auth_conf, consumer.username)
        return public_key, err
    end
end

function _M.rewrite(conf, ctx)
    -- fetch token and hide credentials if necessary
    local jwt_token, err = fetch_jwt_token(conf, ctx)
    if not jwt_token then
        core.log.info("failed to fetch JWT token: ", err)
        return 401, {message = "Missing JWT token in request"}
    end

    local jwt_obj = jwt:load_jwt(jwt_token)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))
    if not jwt_obj.valid then
        core.log.warn("JWT token invalid: ", jwt_obj.reason)
        return 401, {message = "JWT token invalid"}
    end

    local user_key = jwt_obj.payload and jwt_obj.payload.key
    if not user_key then
        return 401, {message = "missing user key in JWT token"}
    end

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "key")

    local consumer = consumers[user_key]
    if not consumer then
        return 401, {message = "Invalid user key in JWT token"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local auth_secret, err = algorithm_handler(consumer)
    if not auth_secret then
        core.log.error("failed to retrieve secrets, err: ", err)
        return 503, {message = "failed to verify jwt"}
    end
    local claim_specs = jwt:get_default_validation_options(jwt_obj)
    claim_specs.lifetime_grace_period = consumer.auth_conf.lifetime_grace_period

    jwt_obj = jwt:verify_jwt_obj(auth_secret, jwt_obj, claim_specs)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))

    if not jwt_obj.verified then
        core.log.warn("failed to verify jwt: ", jwt_obj.reason)
        return 401, {message = "failed to verify jwt"}
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit jwt-auth rewrite")
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

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return core.response.exit(404)
    end

    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "key")

    core.log.info("consumers: ", core.json.delay_encode(consumers))
    local consumer = consumers[key]
    if not consumer then
        return core.response.exit(404)
    end

    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local sign_handler = algorithm_handler(consumer, true)
    local jwt_token = sign_handler(key, consumer, payload)
    if jwt_token then
        return core.response.exit(200, jwt_token)
    end

    return core.response.exit(404)
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/jwt/sign",
            handler = gen_token,
        }
    }
end


return _M
