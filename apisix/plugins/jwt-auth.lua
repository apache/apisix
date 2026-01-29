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
local new_tab = require ("table.new")
local auth_utils = require("apisix.utils.auth")

local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64
local ngx      = ngx
local sub_str  = string.sub
local table_insert = table.insert
local table_concat = table.concat
local ngx_re_gmatch = ngx.re.gmatch
local plugin_name = "jwt-auth"
local schema_def = require("apisix.schema_def")
local jwt_parser = require("apisix.plugins.jwt-auth.parser")

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
        },
        key_claim_name = {
            type = "string",
            default = "key",
            minLength = 1,
        },
        store_in_ctx = {
            type = "boolean",
            default = false
        },
        realm = schema_def.get_realm_schema("jwt"),
        anonymous_consumer = schema_def.anonymous_consumer_schema,
        claims_to_verify = {
            type = "array",
            items = {
                type = "string",
                enum = {"exp","nbf"},
            },
            uniqueItems = true,
            default = {"exp", "nbf"},
        },
    },
}

local consumer_schema = {
    type = "object",
    -- can't use additionalProperties with dependencies
    properties = {
        key = {
            type = "string",
            minLength = 1,
        },
        secret = {
            type = "string",
            minLength = 1,
        },
        algorithm = {
            type = "string",
            enum = {
                "HS256",
                "HS384",
                "HS512",
                "RS256",
                "RS384",
                "RS512",
                "ES256",
                "ES384",
                "ES512",
                "PS256",
                "PS384",
                "PS512",
                "EdDSA",
            },
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
                            enum = {"HS256", "HS384", "HS512"},
                            default = "HS256"
                        },
                    },
                },
                {
                    properties = {
                        public_key = {type = "string"},
                        algorithm = {
                            enum = {
                                "RS256",
                                "RS384",
                                "RS512",
                                "ES256",
                                "ES384",
                                "ES512",
                                "PS256",
                                "PS384",
                                "PS512",
                                "EdDSA",
                            },
                        },
                    },
                    required = {"public_key"},
                },
            }
        }
    },
    encrypt_fields = {"secret"},
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
    local ok, err
    if schema_type == core.schema.TYPE_CONSUMER then
        ok, err = core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end

    if not ok then
        return false, err
    end

    local is_hs_alg = conf.algorithm:sub(1, 2) == "HS"
    if (conf.algorithm == "HS256" or conf.algorithm == "HS512") and not conf.secret then
        return false, "property \"secret\" is required "..
                      "when \"algorithm\" is \"HS256\" or \"HS512\""
    end

    if is_hs_alg and not conf.secret then
        conf.secret = ngx_encode_base64(resty_random.bytes(32, true))
    elseif conf.base64_secret then
        if ngx_decode_base64(conf.secret) == nil then
            return false, "base64_secret required but the secret is not in base64 format"
        end
    end

    if not is_hs_alg and not conf.public_key then
        return false, "missing valid public key"
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

local function get_secret(conf)
    local secret = conf.secret

    if conf.base64_secret then
        return ngx_decode_base64(secret)
    end

    return secret
end


local function get_auth_secret(consumer)
    if not consumer.auth_conf.algorithm or consumer.auth_conf.algorithm:sub(1, 2) == "HS" then
        return get_secret(consumer.auth_conf)
    else
        return consumer.auth_conf.public_key
    end
end


local function find_consumer(conf, ctx)
    -- fetch token and hide credentials if necessary
    local jwt_token, err = fetch_jwt_token(conf, ctx)
    if not jwt_token then
        core.log.info("failed to fetch JWT token: ", err)
        return nil, nil, "Missing JWT token in request"
    end

    local jwt, err = jwt_parser.new(jwt_token)
    if not jwt then
        err = "JWT token invalid: " .. err
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.warn(err)
        return nil, nil, "JWT token invalid"
    end
    core.log.debug("parsed jwt object: ", core.json.delay_encode(jwt, true))

    local key_claim_name = conf.key_claim_name
    local user_key = jwt.payload and jwt.payload[key_claim_name]
    if not user_key then
        return nil, nil, "missing user key in JWT token"
    end

    local consumer, consumer_conf, err = consumer_mod.find_consumer(plugin_name, "key", user_key)
    core.log.warn("dibag cons: ", core.json.delay_encode(consumer))
    if not consumer then
        core.log.warn("failed to find consumer: ", err or "invalid user key")
        return nil, nil, "Invalid user key in JWT token"
    end

    local auth_secret, err = get_auth_secret(consumer)
    if not auth_secret then
        err = "failed to retrieve secrets, err: " .. err
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.error(err)
        return nil, nil, "failed to verify jwt"
    end

    -- Now verify the JWT signature
    if not jwt:verify_signature(auth_secret) then
        local err = "failed to verify jwt: signature mismatch: " .. jwt.signature
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.warn(err)
        return nil, nil, "failed to verify jwt"
    end

    -- Verify the JWT registered claims
    local ok, err = jwt:verify_claims(conf.claims_to_verify, {
        lifetime_grace_period = consumer.auth_conf.lifetime_grace_period
    })
    if not ok then
        err = "failed to verify jwt: " .. err
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.error(err)
        return nil, nil, "failed to verify jwt"
    end

    if conf.store_in_ctx then
        ctx.jwt_auth_payload = jwt.payload
    end

    return consumer, consumer_conf
end


function _M.rewrite(conf, ctx)
    local consumer, consumer_conf, err = find_consumer(conf, ctx)
    if not consumer then
        if not conf.anonymous_consumer then
            core.response.set_header("WWW-Authenticate", "Bearer realm=\"" .. conf.realm .. "\"")
            return 401, { message = err }
        end
        consumer, consumer_conf, err = consumer_mod.get_anonymous_consumer(conf.anonymous_consumer)
        if not consumer then
            err = "jwt-auth failed to authenticate the request, code: 401. error: " .. err
            core.log.error(err)
            core.response.set_header("WWW-Authenticate", "Bearer realm=\"" .. conf.realm .. "\"")
            return 401, { message = "Invalid user authorization"}
        end
    end

    core.log.info("consumer: ", core.json.delay_encode(consumer))

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit jwt-auth rewrite")
end


return _M
