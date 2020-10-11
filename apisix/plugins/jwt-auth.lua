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
local ck       = require("resty.cookie")
local consumer = require("apisix.consumer")
local resty_random = require("resty.random")
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ipairs   = ipairs
local ngx      = ngx
local ngx_time = ngx.time
local sub_str  = string.sub
local plugin_name = "jwt-auth"


local schema = {
    type = "object",
    properties = {
        key = {type = "string"},
        secret = {type = "string"},
        algorithm = {
            type = "string",
            enum = {"HS256", "HS512", "RS256"},
            default = "HS256"
        },
        exp = {type = "integer", minimum = 1},
        base64_secret = {
            type = "boolean",
            default = false
        }
    }
}


local _M = {
    version = 0.1,
    priority = 2510,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_ids)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_ids[consumer.auth_conf.key] = consumer
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

    if not conf.secret then
        conf.secret = ngx_encode_base64(resty_random.bytes(32, true))
    end

    if not conf.exp then
        conf.exp = 60 * 60 * 24
    end

    return true
end


local function fetch_jwt_token(ctx)
    local token = core.request.header(ctx, "authorization")
    if token then
        local prefix = sub_str(token, 1, 7)
        if prefix == 'Bearer ' or prefix == 'bearer ' then
            return sub_str(token, 8)
        end
        return token
    end

    token = ctx.var.arg_jwt
    if token then
        return token
    end

    local cookie, err = ck:new()
    if not cookie then
        return nil, err
    end

    local val, err = cookie:get("jwt")
    return val, err
end

local function get_secret(conf)
    if conf.base64_secret then
        return ngx_decode_base64(conf.secret)
    end
        return conf.secret
end

function _M.rewrite(conf, ctx)
    local jwt_token, err = fetch_jwt_token(ctx)
    if not jwt_token then
        if err and err:sub(1, #"no cookie") ~= "no cookie" then
            core.log.error("failed to fetch JWT token: ", err)
        end

        return 401, {message = "Missing JWT token in request"}
    end

    local jwt_obj = jwt:load_jwt(jwt_token)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))
    if not jwt_obj.valid then
        return 401, {message = jwt_obj.reason}
    end

    local user_key = jwt_obj.payload and jwt_obj.payload.key
    if not user_key then
        return 401, {message = "missing user key in JWT token"}
    end

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    local consumer = consumers[user_key]
    if not consumer then
        return 401, {message = "Invalid user key in JWT token"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local auth_secret = get_secret(consumer.auth_conf)
    jwt_obj = jwt:verify_jwt_obj(auth_secret, jwt_obj)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))
    if not jwt_obj.verified then
        return 401, {message = jwt_obj.reason}
    end

    ctx.consumer = consumer
    ctx.consumer_id = consumer.consumer_id
    ctx.consumer_ver = consumer_conf.conf_version
    core.log.info("hit jwt-auth rewrite")
end


local function gen_token()
    local args = ngx.req.get_uri_args()
    if not args or not args.key then
        return core.response.exit(400)
    end

    local key = args.key

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return core.response.exit(404)
    end

    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    core.log.info("consumers: ", core.json.delay_encode(consumers))
    local consumer = consumers[key]
    if not consumer then
        return core.response.exit(404)
    end

    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local auth_secret = get_secret(consumer.auth_conf)
    local jwt_token = jwt:sign(
        auth_secret,
        {
            header = {
                typ = "JWT",
                alg = consumer.auth_conf.algorithm
            },
            payload = {
                key = key,
                exp = ngx_time() + consumer.auth_conf.exp
            }
        }
    )

    core.response.exit(200, jwt_token)
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
