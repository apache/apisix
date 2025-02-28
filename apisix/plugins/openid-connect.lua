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

local core    = require("apisix.core")
local ngx_re  = require("ngx.re")
local openidc = require("resty.openidc")
local random  = require("resty.random")
local string  = string
local ngx     = ngx
local ipairs  = ipairs
local concat  = table.concat

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
        token_endpoint_auth_method = {
            type = "string",
            default = "client_secret_basic"
        },
        bearer_only = {
            type = "boolean",
            default = false,
        },
        session = {
            type = "object",
            properties = {
                secret = {
                    type = "string",
                    description = "the key used for the encrypt and HMAC calculation",
                    minLength = 16,
                },
                cookie = {
                    type = "object",
                    properties = {
                        lifetime = {
                            type = "integer",
                            description = "it holds the cookie lifetime in seconds in the future",
                        }
                    }
                }
            },
            required = {"secret"},
            additionalProperties = false,
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
            description = "auto append '.apisix/redirect' to ngx.var.uri if not configured"
        },
        post_logout_redirect_uri = {
            type = "string",
            description = "the URI will be redirect when request logout_path",
        },
        unauth_action = {
            type = "string",
            default = "auth",
            enum = {"auth", "deny", "pass"},
            description = "The action performed when client is not authorized. Use auth to " ..
                "redirect user to identity provider, deny to respond with 401 Unauthorized, and " ..
                "pass to allow the request regardless."
        },
        public_key = {type = "string"},
        token_signing_alg_values_expected = {type = "string"},
        use_pkce = {
            description = "when set to true the PKCE(Proof Key for Code Exchange) will be used.",
            type = "boolean",
            default = false
        },
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
        },
        set_refresh_token_header = {
            description = "Whether the refresh token should be added in the X-Refresh-Token " ..
                "header to the request for downstream.",
            type = "boolean",
            default = false
        },
        proxy_opts = {
            description = "HTTP proxy server be used to access identity server.",
            type = "object",
            properties = {
                http_proxy = {
                    type = "string",
                    description = "HTTP proxy like: http://proxy-server:80.",
                },
                https_proxy = {
                    type = "string",
                    description = "HTTPS proxy like: http://proxy-server:80.",
                },
                http_proxy_authorization = {
                    type = "string",
                    description = "Basic [base64 username:password].",
                },
                https_proxy_authorization = {
                    type = "string",
                    description = "Basic [base64 username:password].",
                },
                no_proxy = {
                    type = "string",
                    description = "Comma separated list of hosts that should not be proxied.",
                }
            },
        },
        authorization_params = {
            description = "Extra authorization params to the authorize endpoint",
            type = "object"
        },
        client_rsa_private_key = {
            description = "Client RSA private key used to sign JWT.",
            type = "string"
        },
        client_rsa_private_key_id = {
            description = "Client RSA private key ID used to compute a signed JWT.",
            type = "string"
        },
        client_jwt_assertion_expires_in = {
            description = "Life duration of the signed JWT in seconds.",
            type = "integer",
            default = 60
        },
        renew_access_token_on_expiry = {
            description = "Whether to attempt silently renewing the access token.",
            type = "boolean",
            default = true
        },
        access_token_expires_in = {
            description = "Lifetime of the access token in seconds if expires_in is not present.",
            type = "integer"
        },
        refresh_session_interval = {
            description = "Time interval to refresh user ID token without re-authentication.",
            type = "integer"
        },
        iat_slack = {
            description = "Tolerance of clock skew in seconds with the iat claim in an ID token.",
            type = "integer",
            default = 120
        },
        accept_none_alg = {
            description = "Set to true if the OpenID provider does not sign its ID token.",
            type = "boolean",
            default = false
        },
        accept_unsupported_alg = {
            description = "Ignore ID token signature to accept unsupported signature algorithm.",
            type = "boolean",
            default = true
        },
        access_token_expires_leeway = {
            description = "Expiration leeway in seconds for access token renewal.",
            type = "integer",
            default = 0
        },
        force_reauthorize = {
            description = "Whether to execute the authorization flow when a token has been cached.",
            type = "boolean",
            default = false
        },
        use_nonce = {
            description = "Whether to include nonce parameter in authorization request.",
            type = "boolean",
            default = false
        },
        revoke_tokens_on_logout = {
            description = "Notify authorization server a previous token is no longer needed.",
            type = "boolean",
            default = false
        },
        jwk_expires_in = {
            description = "Expiration time for JWK cache in seconds.",
            type = "integer",
            default = 86400
        },
        jwt_verification_cache_ignore = {
            description = "Whether to ignore cached verification and re-verify.",
            type = "boolean",
            default = false
        },
        cache_segment = {
            description = "Name of a cache segment to differentiate caches.",
            type = "string"
        },
        introspection_interval = {
            description = "TTL of the cached and introspected access token in seconds.",
            type = "integer",
            default = 0
        },
        introspection_expiry_claim = {
            description = "Name of the expiry claim that controls the cached access token TTL.",
            type = "string"
        },
        introspection_addon_headers = {
            description = "Extra http headers in introspection",
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = "^[^:]+$"
            }
        },
        required_scopes = {
            description = "List of scopes that are required to be granted to the access token",
            type = "array",
            items = {
                type = "string"
            }
        },
        valid_issuers = {
            description = [[Whitelist the vetted issuers of the jwt.
            When not passed by the user, the issuer returned by discovery endpoint will be used.
            In case both are missing, the issuer will not be validated.]],
            type = "array",
            items = {
                type = "string"
            }
        },
    },
    encrypt_fields = {"client_secret", "client_rsa_private_key"},
    required = {"client_id", "client_secret", "discovery"}
}


local _M = {
    version = 0.2,
    priority = 2599,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    if conf.ssl_verify == "no" then
        -- we used to set 'ssl_verify' to "no"
        conf.ssl_verify = false
    end

    if not conf.bearer_only and not conf.session then
        core.log.warn("when bearer_only = false, " ..
                       "you'd better complete the session configuration manually")
        conf.session = {
            -- generate a secret when bearer_only = false and no secret is configured
            secret = ngx_encode_base64(random.bytes(32, true) or random.bytes(32))
        }
    end

    local check = {"discovery", "introspection_endpoint", "redirect_uri",
                    "post_logout_redirect_uri", "proxy_opts.http_proxy", "proxy_opts.https_proxy"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function get_bearer_access_token(ctx)
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
        -- No result was returned.
        return false, nil, err
    elseif #res < 2 then
        -- Header doesn't split into enough tokens.
        return false, nil, "Invalid Authorization header format."
    end

    if string.lower(res[1]) == "bearer" then
        -- Return extracted token.
        return true, res[2], nil
    end

    return false, nil, nil
end


local function introspect(ctx, conf)
    -- Extract token, maybe.
    local has_token, token, err = get_bearer_access_token(ctx)

    if err then
        return ngx.HTTP_BAD_REQUEST, err, nil, nil
    end

    if not has_token then
        -- Could not find token.

        if conf.bearer_only then
            -- Token strictly required in request.
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm .. '"'
            return ngx.HTTP_UNAUTHORIZED, "No bearer token found in request.", nil, nil
        else
            -- Return empty result.
            return nil, nil, nil, nil
        end
    end
    local opts = {}
    -- If we get here, token was found in request.
    if conf.use_jwks then
        local valid_issuers
        if conf.valid_issuers then
            valid_issuers = conf.valid_issuers
        else
            local discovery, discovery_err = openidc.get_discovery_doc(conf)
            if discovery_err then
                core.log.warn("OIDC access discovery url failed : ", discovery_err)
            else
                core.log.info("valid_issuers not provided, using issuer from discovery doc: ", discovery.issuer)
                valid_issuers = {discovery.issuer}
            end
        end
        if valid_issuers then
            opts.valid_issuers = valid_issuers
        end
    end
    if conf.public_key or conf.use_jwks then
        -- Validate token against public key or jwks document of the oidc provider.
        -- TODO: In the called method, the openidc module will try to extract
        --  the token by itself again -- from a request header or session cookie.
        --  It is inefficient that we also need to extract it (just from headers)
        --  so we can add it in the configured header. Find a way to use openidc
        --  module's internal methods to extract the token.
        local res, err = openidc.bearer_jwt_verify(conf, opts)
        if err then
            -- Error while validating or token invalid.
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm ..
                '", error="invalid_token", error_description="' .. err .. '"'
            return ngx.HTTP_UNAUTHORIZED, err, nil, nil
        end

        -- Token successfully validated.
        local method = (conf.public_key and "public_key") or (conf.use_jwks and "jwks")
        core.log.debug("token validate successfully by ", method)
        return res, err, token, res
    else
        -- Validate token against introspection endpoint.
        -- TODO: Same as above for public key validation.
        if conf.introspection_addon_headers then
            -- http_request_decorator option provided by lua-resty-openidc
            conf.http_request_decorator = function(req)
                local h = req.headers or {}
                for _, name in ipairs(conf.introspection_addon_headers) do
                    local value = core.request.header(ctx, name)
                    if value then
                        h[name] = value
                    end
                end
                req.headers = h
                return req
            end
        end

        local res, err = openidc.introspect(conf)
        conf.http_request_decorator = nil

        if err then
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm ..
                '", error="invalid_token", error_description="' .. err .. '"'
            return ngx.HTTP_UNAUTHORIZED, err, nil, nil
        end

        -- Token successfully validated and response from the introspection
        -- endpoint contains the userinfo.
        core.log.debug("token validate successfully by introspection")
        return res, err, token, res
    end
end


local function add_access_token_header(ctx, conf, token)
    if token then
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
end

-- Function to split the scope string into a table
local function split_scopes_by_space(scope_string)
    local scopes = {}
    for scope in string.gmatch(scope_string, "%S+") do
        scopes[scope] = true
    end
    return scopes
end

-- Function to check if all required scopes are present
local function required_scopes_present(required_scopes, http_scopes)
    for _, scope in ipairs(required_scopes) do
        if not http_scopes[scope] then
            return false
        end
    end
    return true
end

function _M.rewrite(plugin_conf, ctx)
    local conf = core.table.clone(plugin_conf)

    -- Previously, we multiply conf.timeout before storing it in etcd.
    -- If the timeout is too large, we should not multiply it again.
    if not (conf.timeout >= 1000 and conf.timeout % 1000 == 0) then
        conf.timeout = conf.timeout * 1000
    end

    local path = ctx.var.request_uri

    if not conf.redirect_uri then
        -- NOTE: 'lua-resty-openidc' requires that 'redirect_uri' be
        --       different from 'uri'.  So default to append the
        --       '.apisix/redirect' suffix if not configured.
        local suffix = "/.apisix/redirect"
        local uri = ctx.var.uri
        if core.string.has_suffix(uri, suffix) then
            -- This is the redirection response from the OIDC provider.
            conf.redirect_uri = uri
        else
            if string.sub(uri, -1, -1) == "/" then
                conf.redirect_uri = string.sub(uri, 1, -2) .. suffix
            else
                conf.redirect_uri = uri .. suffix
            end
        end
        core.log.debug("auto set redirect_uri: ", conf.redirect_uri)
    end

    if not conf.ssl_verify then
        -- openidc use "no" to disable ssl verification
        conf.ssl_verify = "no"
    end

    if path == (conf.logout_path or "/logout") then
        local discovery, discovery_err = openidc.get_discovery_doc(conf)
        if discovery_err then
            core.log.error("OIDC access discovery url failed : ", discovery_err)
            return 503
        end
        if conf.post_logout_redirect_uri and not discovery.end_session_endpoint then
            -- If the end_session_endpoint field does not exist in the OpenID Provider Discovery
            -- Metadata, the redirect_after_logout_uri field is used for redirection.
            conf.redirect_after_logout_uri = conf.post_logout_redirect_uri
        end
    end

    local response, err, session, _

    if conf.bearer_only or conf.introspection_endpoint or conf.public_key or conf.use_jwks then
        -- An introspection endpoint or a public key has been configured. Try to
        -- validate the access token from the request, if it is present in a
        -- request header. Otherwise, return a nil response. See below for
        -- handling of the case where the access token is stored in a session cookie.
        local access_token, userinfo
        response, err, access_token, userinfo = introspect(ctx, conf)

        if err then
            -- Error while validating token or invalid token.
            core.log.error("OIDC introspection failed: ", err)
            return response
        end

        if response then
            if conf.required_scopes then
                local http_scopes = response.scope and split_scopes_by_space(response.scope) or {}
                local is_authorized = required_scopes_present(conf.required_scopes, http_scopes)
                if not is_authorized then
                    core.log.error("OIDC introspection failed: ", "required scopes not present")
                    local error_response = {
                        error = "required scopes " .. concat(conf.required_scopes, ", ") ..
                        " not present"
                    }
                    return 403, core.json.encode(error_response)
                end
            end
            -- Add configured access token header, maybe.
            add_access_token_header(ctx, conf, access_token)

            if userinfo and conf.set_userinfo_header then
                -- Set X-Userinfo header to introspection endpoint response.
                core.request.set_header(ctx, "X-Userinfo",
                    ngx_encode_base64(core.json.encode(userinfo)))
            end
        end
    end

    if not response then
        -- Either token validation via introspection endpoint or public key is
        -- not configured, and/or token could not be extracted from the request.

        local unauth_action = conf.unauth_action
        if unauth_action ~= "auth" then
            unauth_action = "deny"
        end

        -- Authenticate the request. This will validate the access token if it
        -- is stored in a session cookie, and also renew the token if required.
        -- If no token can be extracted, the response will redirect to the ID
        -- provider's authorization endpoint to initiate the Relying Party flow.
        -- This code path also handles when the ID provider then redirects to
        -- the configured redirect URI after successful authentication.
        response, err, _, session  = openidc.authenticate(conf, nil, unauth_action, conf.session)

        if err then
            if session then
                session:close()
            end
            if err == "unauthorized request" then
                if conf.unauth_action == "pass" then
                    return nil
                end
                return 401
            end
            core.log.error("OIDC authentication failed: ", err)
            return 500
        end

        if response then
            -- If the openidc module has returned a response, it may contain,
            -- respectively, the access token, the ID token, the refresh token,
            -- and the userinfo.
            -- Add respective headers to the request, if so configured.

            -- Add configured access token header, maybe.
            add_access_token_header(ctx, conf, response.access_token)

            -- Add X-ID-Token header, maybe.
            if response.id_token and conf.set_id_token_header then
                local token = core.json.encode(response.id_token)
                core.request.set_header(ctx, "X-ID-Token", ngx.encode_base64(token))
            end

            -- Add X-Userinfo header, maybe.
            if response.user and conf.set_userinfo_header then
                core.request.set_header(ctx, "X-Userinfo",
                    ngx_encode_base64(core.json.encode(response.user)))
            end

            -- Add X-Refresh-Token header, maybe.
            if session.data.refresh_token and conf.set_refresh_token_header then
                core.request.set_header(ctx, "X-Refresh-Token", session.data.refresh_token)
            end
        end
    end
    if session then
        session:close()
    end
end


return _M
