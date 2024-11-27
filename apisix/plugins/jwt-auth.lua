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
local auth_utils = require("apisix.utils.auth")

local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ngx      = ngx
local sub_str  = string.sub
local table_insert = table.insert
local table_concat = table.concat
local ngx_re_gmatch = ngx.re.gmatch
local plugin_name = "jwt-auth"


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
                        algorithm = {
                            enum = {"RS256", "ES256"},
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

local function get_auth_secret(auth_conf)
    if not auth_conf.algorithm or auth_conf.algorithm == "HS256"
            or auth_conf.algorithm == "HS512" then
        return get_secret(auth_conf)
    elseif auth_conf.algorithm == "RS256" or auth_conf.algorithm == "ES256"  then
        return auth_conf.public_key
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
        err = "JWT token invalid: " .. jwt_obj.reason
        if auth_utils.is_running_under_multi_auth(ctx) then
            return 401, err
        end
        core.log.warn(err)
        return 401, {message = "JWT token invalid"}
    end

    local key_claim_name = conf.key_claim_name
    local user_key = jwt_obj.payload and jwt_obj.payload[key_claim_name]
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

    local auth_secret, err = get_auth_secret(consumer.auth_conf)
    if not auth_secret then
        err = "failed to retrieve secrets, err: " .. err
        if auth_utils.is_running_under_multi_auth(ctx) then
            return 401, err
        end
        core.log.error(err)
        return 503, {message = "failed to verify jwt"}
    end
    local claim_specs = jwt:get_default_validation_options(jwt_obj)
    claim_specs.lifetime_grace_period = consumer.auth_conf.lifetime_grace_period

    jwt_obj = jwt:verify_jwt_obj(auth_secret, jwt_obj, claim_specs)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))

    if not jwt_obj.verified then
        err = "failed to verify jwt: " .. jwt_obj.reason
        if auth_utils.is_running_under_multi_auth(ctx) then
            return 401, err
        end
        core.log.warn(err)
        return 401, {message = "failed to verify jwt"}
    end

    if conf.store_in_ctx then
        ctx.jwt_obj = jwt_obj
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit jwt-auth rewrite")
end


return _M
