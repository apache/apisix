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
local string = string
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
        token_signing_alg_values_expected = {type = "string"},
        set_access_token_header = {
            description = "Whether the access token should be added as a header to the request " ..
                "for downstream",
            type = "boolean",
            default = true
        },
        set_userinfo_token_header = {
            description = "Whether the user info token should be added in the X-Userinfo " ..
                "header to the request for downstream.",
            type = "boolean",
            default = true
        },
        set_id_token_header = {
            description = "Whether the ID token should be added in the X-ID-Token header to " ..
                "the request for downstream.",
            type = "boolean",
            default = true
        },
        access_token_in_authorization_header = {
            description = "Whether the access token should be added in the Authorization " ..
                "header as opposed to the X-Access-Token header.",
            type = "boolean",
            default = false
        }
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


local function check_bearer_access_token(ctx)
    -- Get Authorization header, maybe.
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        -- No Authorization header, get X-Access-Token header, maybe.
        local access_token_header = core.request.header(ctx, "X-Access-Token")
        if not access_token_header then
            -- No X-Access-Token header neither.
            return false, nil, nil
        end

        -- Return extracted header value.
        return true, access_token_header, nil
    end

    -- Check format of Authorization header.
    local res, err = ngx_re.split(auth_header, " ", nil, nil, 2)
    if not res then
        return false, nil, err
    end

    if string.lower(res[1]) == "bearer" then
        -- Return extracted token.
        return true, res[2], nil
    end

    return false
end


local function set_header(ctx, name, value)
    -- Set a request header to the given value and update the cached headers in the context as well.

    -- Set header in request.
    ngx.req.set_header(name, value)

    -- Set header in cache, maybe.
    if ctx and ctx.headers then
        ctx.headers[name] = value
    end
end


local function add_user_header(ctx, user)
    local userinfo = core.json.encode(user)
    set_header(ctx, "X-Userinfo", ngx_encode_base64(userinfo))
end


local function add_access_token_header(ctx, conf, token)
    -- Add Authorization or X-Access-Token header, respectively, if not already set.
    if conf.set_access_token_header then
        if conf.access_token_in_authorization_header then
            if not core.request.header(ctx, "Authorization") then
                -- Add Authorization header.
                set_header(ctx, "Authorization", "Bearer " .. token)
            end
        else
            if not core.request.header(ctx, "X-Access-Token") then
                -- Add X-Access-Token header.
                set_header(ctx, "X-Access-Token", token)
            end
        end
    end
end


local function introspect(ctx, conf)
    -- Extract token, maybe. Ignore errors.
    local has_token, token, _ = check_bearer_access_token(ctx)

    -- Check if token was extracted or if we always require a token in the request.
    if has_token or conf.bearer_only then
        local res, err

        if conf.public_key then
            -- Validate token against public key.
            res, err = openidc.bearer_jwt_verify(conf)
            if res then
                -- Token is valid.

                -- Add configured access token header, maybe.
                add_access_token_header(ctx, conf, token)
                return res
            end
        else
            -- Validate token against introspection endpoint.
            res, err = openidc.introspect(conf)
            if err then
                return ngx.HTTP_UNAUTHORIZED, err
            else
                -- Token is valid and res contains the response from the introspection endpoint.

                if conf.set_userinfo_token_header then
                    -- Set X-Userinfo header to introspection endpoint response.
                    add_user_header(ctx, res)
                end

                -- Add configured access token header, maybe.
                add_access_token_header(ctx, conf, token)
                return res
            end
        end
        if conf.bearer_only then
            -- If we get here, the token could not be validated, but we always require a valid
            -- token in the request.
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm
                                             .. '",error="' .. err .. '"'
            return ngx.HTTP_UNAUTHORIZED, err
        end
    end

    -- Return nil to indicate that a token could not be extracted or validated, but that we don't
    -- want to fail quickly.
    return nil
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
    end

    if not response then
        -- A valid token was not in the request. Try to obtain one by authenticatin against the
        -- configured identity provider.
        local response, err = openidc.authenticate(conf)
        if err then
            core.log.error("failed to authenticate in openidc: ", err)
            return 500
        end

        if response then
            -- Add X-Userinfo header, maybe.
            if response.user and conf.set_userinfo_token_header then
                add_user_header(ctx, response.user)
            end

            -- Add configured access token header, maybe.
            if response.access_token then
                add_access_token_header(ctx, conf, response.access_token)
            end

            -- Add X-ID-Token header, maybe.
            if response.id_token and conf.set_id_token_header then
                local token = core.json.encode(response.id_token)
                set_header(ctx, "X-ID-Token", ngx.encode_base64(token))
            end
        end
    end
end


return _M
