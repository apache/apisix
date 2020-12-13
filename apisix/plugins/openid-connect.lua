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
local core = require("apisix.core")
local ngx_re = require("ngx.re")
local openidc = require("resty.openidc")
local ngx = ngx
local ngx_encode_base64 = ngx.encode_base64

local plugin_name = "openid-connect"


local schema = {
    type = "object",
    properties = {
        client_id = {type = "string"},
        client_secret = {type = "string"},
        discovery = {type = "string"},
        scope = {type = "string"},
        ssl_verify = {type = "boolean"}, -- default is false
        timeout = {type = "integer", minimum = 1}, --default is 3 seconds
        introspection_endpoint = {type = "string"}, --default is nil
        --default is client_secret_basic
        introspection_endpoint_auth_method = {type = "string"},
        bearer_only = {type = "boolean"}, -- default is false
        realm = {type = "string"}, -- default is apisix
        logout_path = {type = "string"}, -- default is /logout
        redirect_uri = {type = "string"}, -- default is ngx.var.request_uri
        public_key = {type = "string"},
        token_signing_alg_values_expected = {type = "string"}
    },
    required = {"client_id", "client_secret", "discovery"}
}


local _M = {
    version = 0.1,
    priority = 2599,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    if conf.ssl_verify == "no" then
        -- we used to set 'ssl_verify' to "no"
        conf.ssl_verify = false
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.scope then
        conf.scope = "openid"
    end
    if not conf.ssl_verify then
        -- we need to use a boolean default value here
        -- so that the schema can pass check in the DP
        conf.ssl_verify = false
    end
    if not conf.timeout then
        conf.timeout = 3
    end
    conf.timeout = conf.timeout * 1000
    if not conf.introspection_endpoint_auth_method then
        conf.introspection_endpoint_auth_method = 'client_secret_basic'
    end
    if not conf.bearer_only then
        conf.bearer_only = false
    end
    if not conf.realm then
        conf.realm = 'apisix'
    end
    if not conf.logout_path then
        conf.logout_path = '/logout'
    end

    return true
end


local function has_bearer_access_token(ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return false
    end

    local res, err = ngx_re.split(auth_header, " ", nil, nil, 2)
    if not res then
        return false, err
    end

    if res[1] == "bearer" then
        return true
    end

    return false
end


local function introspect(ctx, conf)
    if has_bearer_access_token(ctx) or conf.bearer_only then
        local res, err

        if conf.public_key then
            res, err = openidc.bearer_jwt_verify(conf)
            if res then
                return res
            end
        else
            res, err = openidc.introspect(conf)
            if err then
                return ngx.HTTP_UNAUTHORIZED, err
            else
                return res
            end
        end
        if conf.bearer_only then
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm
                                             .. '",error="' .. err .. '"'
            return ngx.HTTP_UNAUTHORIZED, err
        end
    end

    return nil
end


local function add_user_header(user)
    local userinfo = core.json.encode(user)
    ngx.req.set_header("X-Userinfo", ngx_encode_base64(userinfo))
end


function _M.rewrite(plugin_conf, ctx)
    local conf = core.table.clone(plugin_conf)
    if not conf.redirect_uri then
        conf.redirect_uri = ctx.var.request_uri
    end
    if not conf.ssl_verify then
        -- openidc use "no" to disable ssl verification
        conf.ssl_verify = "no"
    end

    local response, err
    if conf.introspection_endpoint or conf.public_key then
        response, err = introspect(ctx, conf)
        if err then
            core.log.error("failed to introspect in openidc: ", err)
            return response
        end
        if response then
            add_user_header(response)
        end
    end

    if not response then
        local response, err = openidc.authenticate(conf)
        if err then
            core.log.error("failed to authenticate in openidc: ", err)
            return 500
        end

        if response then
            if response.user then
                add_user_header(response.user)
            end
            if response.access_token then
                ngx.req.set_header("X-Access-Token", response.access_token)
            end
            if response.id_token then
                local token = core.json.encode(response.id_token)
                ngx.req.set_header("X-ID-Token", ngx.encode_base64(token))
            end
        end
    end
end


return _M
