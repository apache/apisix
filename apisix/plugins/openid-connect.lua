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
        scope = {
            type = "string",
            default = "openid",
        },
        ssl_verify = {
            type = "boolean",
            default = false,
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 3,
            description = "timeout in seconds",
        },
        introspection_endpoint = {
            type = "string"
        },
        introspection_endpoint_auth_method = {
            type = "string",
            default = "client_secret_basic"
        },
        bearer_only = {
            type = "boolean",
            default = false,
        },
        realm = {
            type = "string",
            default = "apisix",
        },
        logout_path = {
            type = "string",
            default = "/logout",
        },
        redirect_uri = {
            type = "string",
            description = "use ngx.var.request_uri if not configured"
        },
        public_key = {type = "string"},
        token_signing_alg_values_expected = {type = "string"},
        set_access_token_header = {
            description = "Whether the access token should be added as a header to the request " ..
                "for downstream",
            type = "boolean",
            default = true
        },
        access_token_in_authorization_header = {
            description = "Whether the access token should be added in the Authorization " ..
                "header as opposed to the X-Access-Token header.",
            type = "boolean",
            default = false
        },
        set_id_token_header = {
            description = "Whether the ID token should be added in the X-ID-Token header to " ..
                "the request for downstream.",
            type = "boolean",
            default = true
        },
        set_userinfo_header = {
            description = "Whether the user info token should be added in the X-Userinfo " ..
                "header to the request for downstream.",
            type = "boolean",
            default = true
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


local function add_access_token_header(ctx, conf, token)
    -- Add Authorization or X-Access-Token header, respectively, if not already set.
    if conf.set_access_token_header then
        if conf.access_token_in_authorization_header then
            if not core.request.header(ctx, "Authorization") then
                -- Add Authorization header.
                core.request.set_header(ctx, "Authorization", "Bearer " .. token)
            end
        else
            if not core.request.header(ctx, "X-Access-Token") then
                -- Add X-Access-Token header.
                core.request.set_header(ctx, "X-Access-Token", token)
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

                if conf.set_userinfo_header then
                    -- Set X-Userinfo header to introspection endpoint response.
                    core.request.set_header(ctx, "X-Userinfo", ngx_encode_base64(core.json.encode(res)))
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

    -- Previously, we multiply conf.timeout before storing it in etcd.
    -- If the timeout is too large, we should not multiply it again.
    if not (conf.timeout >= 1000 and conf.timeout % 1000 == 0) then
        conf.timeout = conf.timeout * 1000
    end

    if not conf.redirect_uri then
        conf.redirect_uri = ctx.var.request_uri
    end

    if not conf.ssl_verify then
        -- openidc use "no" to disable ssl verification
        conf.ssl_verify = "no"
    end

    local response, err
    if conf.introspection_endpoint or conf.public_key then
        -- Try to introspect access token from request, if it is present.
        -- Returns a nil response if token is not found.
        response, err = introspect(ctx, conf)

        if err then
            -- Unable to introspect. Fail quickly.
            core.log.error("failed to introspect in openidc: ", err)
            return response
        end
    end

    if not response then
        -- Response has not yet been determined. Either no token was found in
        -- the request or introspection is not set up.

        -- Authenticate the request. This will check and validate the token if
        -- it is stored in the openidc module's session cookie, or divert to the
        -- authorization endpoint of the ID provider.
        local response, err = openidc.authenticate(conf)

        if err then
            core.log.error("failed to authenticate in openidc: ", err)
            return 500
        end

        if response then
            -- If the openidc module has returned a response, it may contain,
            -- respectively, the access token, ID token, and userinfo. Add
            -- respective headers to the request, if so configured.

            -- Add configured access token header, maybe.
            if response.access_token then
                add_access_token_header(ctx, conf, response.access_token)
            end

            -- Add X-ID-Token header, maybe.
            if response.id_token and conf.set_id_token_header then
                local token = core.json.encode(response.id_token)
                core.request.set_header(ctx, "X-ID-Token", ngx.encode_base64(token))
            end

            -- Add X-Userinfo header, maybe.
            if response.user and conf.set_userinfo_header then
                core.request.set_header(ctx, "X-Userinfo", ngx_encode_base64(core.json.encode(response.user)))
            end
        end
    end
end


return _M
