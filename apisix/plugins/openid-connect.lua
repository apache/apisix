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

local core              = require("apisix.core")
local secret            = require("apisix.secret")
local ngx_re            = require("ngx.re")
local openidc           = require("resty.openidc")
local jsonschema        = require('jsonschema')
local pkey              = require("resty.openssl.pkey")
local dump_jwk          = require("resty.openssl.auxiliary.jwk").dump_jwk
local redis             = require("apisix.utils.redis")
local string            = string
local ngx               = ngx
local ipairs            = ipairs
local type              = type
local tostring          = tostring
local tonumber          = tonumber
local pcall             = pcall
local concat            = table.concat
local unpack            = unpack

local ngx_encode_base64 = ngx.encode_base64

local plugin_name       = "openid-connect"

-- returned verbatim by resty.openidc when the state in the authorization
-- callback does not match the one restored from the session; the string is
-- identical in lua-resty-openidc 1.8.0 and 1.9.0
local STATE_MISMATCH_ERR =
    "state from argument does not match state restored from session"

-- OIDC Back-Channel Logout 1.0
-- (https://openid.net/specs/openid-connect-backchannel-1_0.html)
local BCL_EVENT = "http://schemas.openid.net/event/backchannel-logout"
-- Acceptance window for the logout token's iat, mirroring
-- mod_auth_openidc's default OIDCIDTokenIatSlack.
local BCL_IAT_SLACK = 600
-- A seen jti only needs to be remembered while a token whose iat is still
-- inside the acceptance window could arrive.
local BCL_JTI_TTL = 2 * BCL_IAT_SLACK + 10
-- Fallback lifetime of a revocation entry when the session has no
-- absolute_timeout: an entry only needs to outlive the sessions it revokes.
local BCL_DENYLIST_TTL = 86400


-- Session config is passed as-is to resty.session.start(); the only
-- translation is the legacy session.cookie.lifetime alias from the
-- lua-resty-session 3.x schema, which is mapped to absolute_timeout
-- when the latter is unset.
local function build_session_opts(session_conf)
    if not session_conf then
        return nil
    end
    if session_conf.cookie and session_conf.cookie.lifetime then
        if not session_conf.absolute_timeout then
            session_conf.absolute_timeout = session_conf.cookie.lifetime
            core.log.warn("session.cookie.lifetime is deprecated; ",
                          "use session.absolute_timeout instead")
        end
    end
    return session_conf
end


-- The nested par/dpop objects own these lua-resty-openidc option names. The
-- root schema accepts unknown properties, so without an explicit rejection a
-- config could set them directly and reach the library unvalidated: the flat
-- DPoP key is not covered by encrypt_fields and would be stored in etcd in
-- plaintext, and the flat PAR endpoint would skip the https check.
local reserved_flat_opts = {
    {name = "use_par", owner = "par.enabled"},
    {name = "pushed_authorization_request_endpoint", owner = "par.endpoint"},
    {name = "pushed_authorization_request_endpoint_auth_method",
     owner = "par.endpoint_auth_method"},
    {name = "use_dpop", owner = "dpop.enabled"},
    {name = "dpop_signing_alg", owner = "dpop.signing_alg"},
    {name = "dpop_private_key", owner = "dpop.private_key"},
    {name = "dpop_public_jwk", owner = "dpop.public_jwk"},
}

-- lua-resty-openidc builds the DPoP proof with resty.openssl, so the JWK has
-- to match the signing algorithm: ES256 signs with an EC key on P-256 per
-- RFC 7518, RS256 and PS256 with an RSA one.
local dpop_alg_key_type = {
    ES256 = {kty = "EC", crv = "P-256"},
    RS256 = {kty = "RSA"},
    PS256 = {kty = "RSA"},
}

local dpop_jwk_required_members = {
    EC = {"crv", "x", "y"},
    RSA = {"e", "n"},
}

-- resty.jwt selects the signer from the algorithm and not from the key, so an
-- EC algorithm handed an RSA key terminates the worker with a SIGSEGV; the
-- curve matters too, since ES512 on a P-256 key emits a P-256 signature
local client_assertion_key_type = {
    RS256 = {kty = "RSA"},
    RS512 = {kty = "RSA"},
    ES256 = {kty = "EC", crv = "P-256"},
    ES512 = {kty = "EC", crv = "P-521"},
}

-- the client authentication methods lua-resty-openidc can use, and the
-- credential each one needs
local token_auth_method_credential = {
    client_secret_basic = false,
    client_secret_post = false,
    private_key_jwt = "client_rsa_private_key",
    client_secret_jwt = "client_secret",
}


local function flatten_openidc_options(conf)
    if conf.par then
        conf.use_par = conf.par.enabled
        conf.pushed_authorization_request_endpoint = conf.par.endpoint
        conf.pushed_authorization_request_endpoint_auth_method =
            conf.par.endpoint_auth_method
        conf.par = nil
    end

    if conf.dpop then
        conf.use_dpop = conf.dpop.enabled
        conf.dpop_signing_alg = conf.dpop.signing_alg
        conf.dpop_private_key = conf.dpop.private_key
        conf.dpop_public_jwk = conf.dpop.public_jwk
        conf.dpop = nil
    end
end


-- Redis connection fields shaped after lua-resty-session's session.redis
-- options; shared by session storage and the back-channel logout store so
-- both expose an identical config surface.
local session_redis_schema = {
    type = "object",
    properties = {
        host = {
            type = "string", minLength = 2, default = "127.0.0.1"
        },
        port = {
            type = "integer", minimum = 1, default = 6379,
        },
        username = {
            type = "string", minLength = 1,
        },
        password = {
            type = "string", minLength = 0,
        },
        database = {
            type = "integer", minimum = 0, default = 0,
            description = "redis database index",
        },
        prefix = {
            type = "string",
            default = "sessions",
            description = "prefix for keys stored in redis"
        },
        ssl = {
            type = "boolean", default = false,
            description = "enable ssl",
        },
        ssl_verify = {
            type = "boolean", default = true,
            description = "verify ssl certificate",
        },
        server_name = {
            type = "string",
            description = "The server name for the new TLS SNI extension.",
        },
        connect_timeout = {
            type = "integer", minimum = 1, default = 1000,
            description = "connect timeout in milliseconds",
        },
        send_timeout = {
            type = "integer", minimum = 1, default = 1000,
            description = "send timeout in milliseconds",
        },
        read_timeout = {
            type = "integer", minimum = 1, default = 1000,
            description = "read timeout in milliseconds",
        },
        keepalive_timeout = {
            type = "integer", minimum = 1000, default = 10000,
            description = "keepalive timeout in milliseconds",
        },
    }
}

local bcl_redis_schema = core.table.deepcopy(session_redis_schema)
bcl_redis_schema.properties.prefix.default = "bcl"

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
            default = true,
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
                cookie_name = {
                    type = "string",
                    description = "session cookie name",
                },
                cookie_path = {
                    type = "string",
                    description = "cookie path scope",
                },
                cookie_domain = {
                    type = "string",
                    description = "cookie domain scope",
                },
                cookie_secure = {
                    type = "boolean",
                    description = "if true, set the Secure cookie attribute",
                },
                cookie_http_only = {
                    type = "boolean",
                    description = "if true, set the HttpOnly cookie attribute",
                },
                cookie_same_site = {
                    type = "string",
                    enum = {"Strict", "Lax", "None", "Default"},
                    description = "SameSite cookie attribute",
                },
                idling_timeout = {
                    type = "integer",
                    description = "idling timeout in seconds",
                },
                rolling_timeout = {
                    type = "integer",
                    description = "rolling timeout in seconds",
                },
                absolute_timeout = {
                    type = "integer",
                    description = "absolute session lifetime in seconds",
                },
                cookie = {
                    type = "object",
                    description =
                        "Deprecated. Kept for backward compatibility with "
                        .. "the lua-resty-session 3.x schema. Use the flat "
                        .. "session.* options (cookie_name, absolute_timeout, "
                        .. "etc.) instead.",
                    properties = {
                        lifetime = {
                            type = "integer",
                            description =
                                "Deprecated. Mapped to absolute_timeout at "
                                .. "runtime when absolute_timeout is not set.",
                        },
                    },
                },
                storage = {
                    type = "string",
                    enum = {"cookie", "redis"},
                    default = "cookie",
                },
                redis = session_redis_schema,
            },
            required = {"secret"},
            ["if"] = {
                properties = {
                    storage = { enum = {"redis"} },
                },
            },
            ["then"] = {
                required = {"redis"},
            },
            additionalProperties = false,
        },
        backchannel_logout = {
            type = "object",
            description = "OIDC Back-Channel Logout 1.0 receiver: the identity "
                .. "provider POSTs a logout_token to `path`, and the revoked "
                .. "session is rejected from the next request on.",
            properties = {
                path = {
                    type = "string",
                    pattern = "^/",
                    description = "in-route path that receives the provider's "
                        .. "back-channel logout POST",
                },
                storage = {
                    type = "string",
                    enum = {"shm", "redis"},
                    default = "shm",
                    description = "where revocations are stored; shm is "
                        .. "per-instance, redis is shared across nodes",
                },
                redis = bcl_redis_schema,
            },
            required = {"path"},
            additionalProperties = false,
        },
        realm = {
            type = "string",
            default = "apisix",
        },
        claim_validator = {
            type = "object",
            properties = {
                issuer = {
                    description = [[Whitelist the vetted issuers of the jwt.
                    When not passed by the user, the issuer returned by
                    discovery endpoint will be used. In case both are missing,
                    the issuer will not be validated.]],
                    type = "object",
                    properties = {
                        valid_issuers = {
                            type = "array",
                            items = {
                                type = "string"
                            }
                        }
                    }
                },
                audience = {
                    type = "object",
                    description = "audience claim value to validate",
                    properties = {
                        claim = {
                            type = "string",
                            description = "custom claim name",
                            default = "aud",
                        },
                        required = {
                            type = "boolean",
                            description = "audience claim is required",
                            default = false,
                        },
                        match_with_client_id = {
                            type = "boolean",
                            description = "audience must euqal to or includes client_id",
                            default = false,
                        }
                    },
                },
            },
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
        use_jwks = {
            type = "boolean",
            default = false,
            description = "If true and if `public_key` is not set, use the JWKS to verify JWT " ..
                "signature and skip token introspection in client credentials flow. The JWKS " ..
                "endpoint is parsed from the discovery document."
        },
        token_signing_alg_values_expected = {type = "string"},
        use_pkce = {
            description = "when set to true the PKCE(Proof Key for Code Exchange) will be used.",
            type = "boolean",
            default = false
        },
        par = {
            description = "Pushed Authorization Requests (PAR) configuration.",
            type = "object",
            properties = {
                enabled = {
                    description = "When true, use Pushed Authorization Requests (PAR).",
                    type = "boolean",
                    default = false,
                },
                endpoint = {
                    description = "URL of the Pushed Authorization Requests endpoint.",
                    type = "string",
                },
                endpoint_auth_method = {
                    description = "Authentication method for the PAR endpoint.",
                    type = "string",
                    enum = {"client_secret_basic", "client_secret_post",
                            "private_key_jwt", "client_secret_jwt"},
                },
            },
            additionalProperties = false,
        },
        dpop = {
            description = "Demonstrating Proof-of-Possession (DPoP) configuration.",
            type = "object",
            properties = {
                enabled = {
                    description = "When true, use DPoP proof JWTs.",
                    type = "boolean",
                    default = false,
                },
                signing_alg = {
                    description = "DPoP proof JWT signing algorithm.",
                    type = "string",
                    enum = {"ES256", "RS256", "PS256"},
                    default = "ES256",
                },
                private_key = {
                    description = "Private key used to sign DPoP proof JWTs.",
                    type = "string",
                },
                public_jwk = {
                    description = "Public JWK matching dpop.private_key.",
                    type = "object",
                    ["not"] = {anyOf = {
                        {required = {"d"}},
                        {required = {"p"}},
                        {required = {"q"}},
                        {required = {"dp"}},
                        {required = {"dq"}},
                        {required = {"qi"}},
                        {required = {"oth"}},
                        {required = {"k"}},
                    }},
                },
            },
            ["if"] = {
                properties = {
                    enabled = { const = true },
                },
            },
            ["then"] = {
                required = {"private_key", "public_jwk"},
            },
            additionalProperties = false,
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
        set_raw_id_token_header = {
            description = "Whether the raw signed ID token JWT should be added in the " ..
                "X-Raw-ID-Token header to the request for downstream.",
            type = "boolean",
            default = false
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
        -- resty.jwt signs the client assertion and raises an uncaught Lua
        -- error for an algorithm it cannot handle, so an unconstrained value
        -- would surface as a 500 per request instead of a rejected config.
        -- Two rocks provide resty/jwt.lua here: the api7-lua-resty-jwt this
        -- rockspec pins, and the lua-resty-jwt lua-resty-openidc depends on.
        -- This enum is what the api7 fork signs, a subset of what the other
        -- one signs, so it holds whichever of the two ends up installed.
        client_jwt_assertion_alg = {
            description = "Signing algorithm for the client assertion JWT.",
            type = "string",
            enum = {"HS256", "HS512", "RS256", "RS512", "ES256", "ES512"}
        },
        client_jwt_assertion_audience = {
            description = "Audience for the client assertion JWT.",
            type = "string"
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
        claim_schema = {
            description = "JSON schema of OIDC response claim",
            type = "object",
            default = nil,
        }
    },
    encrypt_fields = {"client_secret", "client_rsa_private_key", "dpop.private_key",
                      "session.secret", "session.redis.password",
                      "backchannel_logout.redis.password"},
    required = {"client_id", "discovery"}
}


local _M = {
    version = 0.2,
    priority = 2599,
    name = plugin_name,
    schema = schema,
    _build_session_opts = build_session_opts,
    _flatten_openidc_options = flatten_openidc_options,
}

-- lua-resty-openidc rejects a JWK that lacks the members its key type needs,
-- but only once the first authorization request builds the thumbprint, which
-- surfaces as a 500 per request instead of a rejected configuration.
-- The public JWK openssl derives from a private key, so a configured JWK can
-- be checked against the key that will actually sign with it.
local function private_key_jwk(pem, field)
    local key, err = pkey.new(pem)
    if not key then
        return nil, "property \"" .. field .. "\" is not a valid key: " .. tostring(err)
    end
    if not key:is_private() then
        return nil, "property \"" .. field .. "\" has no private key in it"
    end

    local ok, dumped = pcall(dump_jwk, key, false)
    if not ok or not dumped then
        return nil, "property \"" .. field .. "\" could not be read as a JWK"
    end

    local jwk
    jwk, err = core.json.decode(dumped)
    if not jwk then
        return nil, "property \"" .. field .. "\" could not be read as a JWK: "
                    .. tostring(err)
    end
    return jwk
end


local function check_dpop_key(dpop)
    -- lua-resty-openidc reads none of this while use_dpop is false, so a
    -- configuration that stages the key material before turning DPoP on is
    -- valid and must not be rejected
    if not (dpop and dpop.enabled) then
        return true
    end

    local jwk = dpop.public_jwk
    if not jwk then
        return true
    end

    local required = dpop_jwk_required_members[jwk.kty]
    if not required then
        return false, "property \"dpop.public_jwk\" validation failed: kty \""
                      .. tostring(jwk.kty) .. "\" is not supported"
    end

    for _, member in ipairs(required) do
        if jwk[member] == nil then
            return false, "property \"dpop.public_jwk\" validation failed: kty \""
                          .. jwk.kty .. "\" requires " .. concat(required, ", ")
        end
        -- the members go into the RFC 7638 thumbprint verbatim, so a non-string
        -- would be encoded as itself and produce a thumbprint no OP can match
        if type(jwk[member]) ~= "string" or jwk[member] == "" then
            return false, "property \"dpop.public_jwk\" validation failed: \""
                          .. member .. "\" must be a non-empty string"
        end
    end

    local expected = dpop_alg_key_type[dpop.signing_alg]
    if not expected then
        return true
    end

    if expected.kty ~= jwk.kty then
        return false, "property \"dpop.signing_alg\" \"" .. dpop.signing_alg
                      .. "\" requires an " .. expected.kty .. " \"dpop.public_jwk\""
    end
    if expected.crv and jwk.crv ~= expected.crv then
        return false, "property \"dpop.signing_alg\" \"" .. dpop.signing_alg
                      .. "\" requires \"dpop.public_jwk\" crv \"" .. expected.crv
                      .. "\", got \"" .. tostring(jwk.crv) .. "\""
    end

    -- The proof is signed with the private key and advertises the JWK, so the
    -- two have to be the same key pair: otherwise the OP gets a proof it
    -- cannot verify. Comparing the derived JWK covers that, and with it the
    -- private key's own type and curve.
    local private_key = dpop.private_key
    if not private_key or secret.is_secret_ref(private_key) then
        return true
    end

    local derived, err = private_key_jwk(private_key, "dpop.private_key")
    if not derived then
        return false, err
    end

    for _, member in ipairs({"kty", unpack(required)}) do
        if derived[member] ~= jwk[member] then
            return false, "property \"dpop.public_jwk\" is not the public key of "
                          .. "\"dpop.private_key\": " .. member .. " is \""
                          .. tostring(derived[member]) .. "\""
        end
    end

    return true
end


-- Which endpoints a configuration can actually reach, and with which client
-- authentication method. rewrite() only calls introspect() when one of
-- bearer_only/introspection_endpoint/public_key/use_jwks is set, and inside it
-- public_key and use_jwks take the local JWT verification branch instead. The
-- token and PAR endpoints belong to the authorization code flow, which
-- bearer_only never runs.
local function reachable_jwt_auth(conf)
    local reachable = {}

    if not (conf.public_key or conf.use_jwks)
       and (conf.bearer_only or conf.introspection_endpoint) then
        core.table.insert(reachable, {name = "introspection_endpoint_auth_method",
                                      method = conf.introspection_endpoint_auth_method})
    end

    if not conf.bearer_only then
        -- ensure_config() replaces an unusable token_endpoint_auth_method
        -- before any endpoint is called (openidc.lua:1209), so it only counts
        -- while its credential is there
        local method = conf.token_endpoint_auth_method
        local credential = token_auth_method_credential[method]
        if credential == nil or credential == false or conf[credential] then
            core.table.insert(reachable, {name = "token_endpoint_auth_method",
                                          method = method})
        end

        -- an explicit PAR method reaches the request unchanged; without one
        -- PAR uses the resolved token method, which is already counted above
        if conf.par and conf.par.enabled and conf.par.endpoint_auth_method then
            core.table.insert(reachable, {name = "par.endpoint_auth_method",
                                          method = conf.par.endpoint_auth_method})
        end
    end

    return reachable
end


-- The token endpoint only logs and falls back when its auth method cannot be
-- used, but the PAR request fails outright (openidc.lua:547), which surfaces
-- as a 500. Only an explicit PAR method gets there unchanged: without one PAR
-- uses whatever ensure_config() resolved, which is usable by construction.
local function check_par_auth_method(conf)
    if conf.bearer_only or not (conf.par and conf.par.enabled) then
        return true
    end

    local method = conf.par.endpoint_auth_method
    if not method then
        return true
    end

    local credential = token_auth_method_credential[method]
    if credential and not conf[credential] then
        return false, "property \"par.endpoint_auth_method\" \"" .. method
                      .. "\" requires \"" .. credential .. "\" when \"par.enabled\" is true"
    end

    return true
end


-- The client assertion is signed with a single algorithm, but each endpoint
-- picks its own auth method. lua-resty-openidc rejects a symmetric algorithm
-- with private_key_jwt and an asymmetric one with client_secret_jwt when the
-- endpoint is called, which surfaces as a 500. With no algorithm configured
-- the library defaults per auth method, so the families cannot conflict.
local function check_client_jwt_assertion_alg(conf)
    local alg = conf.client_jwt_assertion_alg
    if not alg then
        return true
    end

    local asymmetric_by, symmetric_by
    for _, selection in ipairs(reachable_jwt_auth(conf)) do
        if selection.method == "private_key_jwt" then
            asymmetric_by = asymmetric_by or selection.name
        elseif selection.method == "client_secret_jwt" then
            symmetric_by = symmetric_by or selection.name
        end
    end

    if asymmetric_by and symmetric_by then
        return false, "property \"client_jwt_assertion_alg\" is a single algorithm, "
                      .. "but \"" .. asymmetric_by .. "\" selects private_key_jwt and \""
                      .. symmetric_by .. "\" selects client_secret_jwt"
    end

    local is_symmetric = alg:sub(1, 2) == "HS"
    if asymmetric_by and is_symmetric then
        return false, "property \"client_jwt_assertion_alg\" \"" .. alg
                      .. "\" is symmetric and cannot be used with the private_key_jwt "
                      .. "selected by \"" .. asymmetric_by .. "\""
    end
    if symmetric_by and not is_symmetric then
        return false, "property \"client_jwt_assertion_alg\" \"" .. alg
                      .. "\" is asymmetric and cannot be used with the client_secret_jwt "
                      .. "selected by \"" .. symmetric_by .. "\""
    end

    -- resty.jwt picks the signer from the algorithm, not the key: handing an
    -- EC algorithm an RSA key terminates the worker with a SIGSEGV in the
    -- signature conversion, and an EC key on the wrong curve silently emits a
    -- signature of the wrong size
    local expected = asymmetric_by and client_assertion_key_type[alg]
    local private_key = conf.client_rsa_private_key
    if not expected or not private_key or secret.is_secret_ref(private_key) then
        return true
    end

    local derived, err = private_key_jwk(private_key, "client_rsa_private_key")
    if not derived then
        return false, err
    end
    if derived.kty ~= expected.kty then
        return false, "property \"client_jwt_assertion_alg\" \"" .. alg
                      .. "\" requires an " .. expected.kty .. " \"client_rsa_private_key\""
    end
    if expected.crv and derived.crv ~= expected.crv then
        return false, "property \"client_jwt_assertion_alg\" \"" .. alg
                      .. "\" requires a \"client_rsa_private_key\" on curve \""
                      .. expected.crv .. "\", got \"" .. tostring(derived.crv) .. "\""
    end

    return true
end
function _M.check_schema(conf)
    if conf.ssl_verify == "no" then
        -- we used to set 'ssl_verify' to "no"
        conf.ssl_verify = false
    end

    if not conf.bearer_only and not conf.session then
        return false, "property \"session.secret\" is required when \"bearer_only\" is false"
    end

    -- client_secret is not required in certain authentication modes. The exemption
    -- is scoped to the flow each alternative actually applies to:
    --   bearer_only=true + public_key/use_jwks: local JWT verification, no IdP call needed
    --   bearer_only=true + introspection_endpoint_auth_method=private_key_jwt: introspection
    --     endpoint authenticates via signed JWT instead of client_secret
    --   token_endpoint_auth_method=private_key_jwt (non-bearer): token endpoint uses signed
    --     JWT; this exemption applies only to the session/callback flow, not bearer mode
    --   use_pkce=true (non-bearer): public-client PKCE flow needs no client_secret
    local client_secret_optional
    if conf.bearer_only then
        client_secret_optional = (conf.public_key or conf.use_jwks)
            or (conf.introspection_endpoint_auth_method == "private_key_jwt")
    else
        client_secret_optional = (conf.token_endpoint_auth_method == "private_key_jwt")
            or conf.use_pkce
    end
    if not client_secret_optional and not conf.client_secret then
        return false, "property \"client_secret\" is required"
    end

    local check = {"discovery", "introspection_endpoint", "redirect_uri",
                    "post_logout_redirect_uri", "par.endpoint", "proxy_opts.http_proxy",
                    "proxy_opts.https_proxy"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.backchannel_logout then
        if conf.bearer_only then
            return false, "backchannel_logout cannot be used with bearer_only"
        end
        if conf.backchannel_logout.storage == "redis"
           and not conf.backchannel_logout.redis
           and not (conf.session and conf.session.redis) then
            return false, "backchannel_logout.redis is required when " ..
                          "backchannel_logout.storage is redis and " ..
                          "session.redis is not configured"
        end
        -- revocation is keyed off the id_token's sid/sub claims, so a restricted
        -- session_contents must still keep id_token, else requests silently skip the denylist.
        if type(conf.session_contents) == "table" and not conf.session_contents.id_token then
            return false, "backchannel_logout requires session_contents.id_token " ..
                          "to be true when session_contents is configured, because " ..
                          "session revocation is keyed off the id_token's sid/sub claims"
        end
    end

    if conf.claim_schema and not secret.is_secret_ref(conf.claim_schema) then
        local ok, res = pcall(jsonschema.generate_validator, conf.claim_schema)
        if not ok then
            return false, "check claim_schema failed: " .. tostring(res)
        end
    end

    for _, opt in ipairs(reserved_flat_opts) do
        if conf[opt.name] ~= nil then
            return false, "property \"" .. opt.name .. "\" is not allowed, use \""
                          .. opt.owner .. "\" instead"
        end
    end

    ok, err = check_dpop_key(conf.dpop)
    if not ok then
        return false, err
    end

    ok, err = check_client_jwt_assertion_alg(conf)
    if not ok then
        return false, err
    end

    ok, err = check_par_auth_method(conf)
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
        local access_token_header = ctx.openid_connect_client_x_access_token
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

    if conf.public_key or conf.use_jwks then
        local opts = {}
        -- Validate token against public key or jwks document of the oidc provider.
        -- TODO: In the called method, the openidc module will try to extract
        --  the token by itself again -- from a request header or session cookie.
        --  It is inefficient that we also need to extract it (just from headers)
        --  so we can add it in the configured header. Find a way to use openidc
        --  module's internal methods to extract the token.
        local valid_issuers
        if conf.claim_validator and conf.claim_validator.issuer then
            valid_issuers = conf.claim_validator.issuer.valid_issuers
        end
        if not valid_issuers then
            local discovery, discovery_err = openidc.get_discovery_doc(conf)
            if discovery_err then
                core.log.warn("OIDC access discovery url failed : ", discovery_err)
            else
                core.log.info("valid_issuers not provided explicitly," ..
                              " using issuer from discovery doc: ",
                              discovery.issuer)
                valid_issuers = {discovery.issuer}
            end
        end
        if valid_issuers then
            opts.valid_issuers = valid_issuers
        end
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
    if token and conf.set_access_token_header then
        if conf.access_token_in_authorization_header then
            core.request.set_header(ctx, "Authorization", "Bearer " .. token)
        else
            core.request.set_header(ctx, "X-Access-Token", token)
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

local function validate_claims_in_oidcauth_response(resp, conf)
    if not conf.claim_schema then
        return true
    end
    local data = {
        user         = resp.user,
        access_token = resp.access_token,
        id_token     = resp.id_token,
    }
    return core.schema.check(conf.claim_schema, data)
end


local function bcl_redis_conf(conf)
    return conf.backchannel_logout.redis
           or (conf.session and conf.session.redis)
end


local function bcl_redis_connect(rconf)
    local red, err = redis.new({
        redis_host = rconf.host,
        redis_port = rconf.port,
        redis_username = rconf.username,
        redis_password = rconf.password,
        redis_database = rconf.database,
        redis_ssl = rconf.ssl,
        redis_ssl_verify = rconf.ssl_verify,
        redis_timeout = rconf.connect_timeout,
    })
    if not red then
        return nil, "failed to connect to redis: " .. err
    end
    return red
end


-- One revocation (or seen-jti) entry per key; the value is the unix time
-- the entry was written.
local function bcl_store_set(conf, key, ttl)
    local now = ngx.time()

    if conf.backchannel_logout.storage == "redis" then
        local rconf = bcl_redis_conf(conf)
        local red, err = bcl_redis_connect(rconf)
        if not red then
            return false, err
        end
        local ok
        ok, err = red:set(rconf.prefix .. ":" .. key, now, "EX", ttl)
        if not ok then
            return false, "failed to write to redis: " .. err
        end
        red:set_keepalive(rconf.keepalive_timeout, 100)
        return true
    end

    local dict = ngx.shared.bcl
    if not dict then
        return false, "shared dict \"bcl\" is missing"
    end
    -- safe_set: evicting an unexpired revocation to make room would silently
    -- re-admit a revoked session, so a full dict must fail the write instead.
    local ok, err = dict:safe_set(key, now, ttl)
    if not ok then
        return false, "failed to write to the shared dict: " .. err
    end
    return true
end


-- Returns the entry timestamp, nil when there is no entry, or nil plus an
-- error when the store cannot be reached (the caller treats that as
-- "no verdict", never as "clean").
local function bcl_store_get(conf, key)
    if conf.backchannel_logout.storage == "redis" then
        local rconf = bcl_redis_conf(conf)
        local red, err = bcl_redis_connect(rconf)
        if not red then
            return nil, err
        end
        local v
        v, err = red:get(rconf.prefix .. ":" .. key)
        if err then
            return nil, "failed to read from redis: " .. err
        end
        red:set_keepalive(rconf.keepalive_timeout, 100)
        if v == ngx.null then
            return nil
        end
        return tonumber(v)
    end

    local dict = ngx.shared.bcl
    if not dict then
        return nil, "shared dict \"bcl\" is missing"
    end
    return dict:get(key)
end


-- The issuer scopes sid/sub values (unique per issuer, Back-Channel Logout
-- 1.0 section 2.4); the client_id additionally scopes the entry to the
-- client the logout token's aud named, so two clients of the same realm
-- sharing a store cannot revoke each other's sessions.
local function bcl_denylist_key(kind, conf, issuer, value)
    return "bcl:" .. kind .. ":" .. issuer .. "#" .. conf.client_id .. "#" .. value
end


-- Validates a logout token per Back-Channel Logout 1.0 section 2.6 and
-- returns its claims. Signature verification (JWKS fetch and cache via the
-- discovery document, kid rollover, "none"-alg rejection) and exp checking
-- (only when the claim is present; older providers omit it) are delegated
-- to resty.openidc's JWT machinery.
local function bcl_validate_logout_token(conf, discovery, logout_token)
    conf.jwt_verification_cache_ignore = true
    conf.token_signing_alg_values_expected =
        discovery.id_token_signing_alg_values_supported

    -- BCL endpoint is unauthenticated: always require a real JWKS-verified
    -- signature, never alg:none or a static public_key.
    conf.accept_none_alg = false
    conf.public_key = nil

    local claims, err = openidc.jwt_verify(logout_token, conf)
    if err then
        return nil, "signature validation failed: " .. err
    end

    if claims.iss ~= discovery.issuer then
        return nil, "iss does not match the discovery issuer"
    end

    local aud_ok = false
    if type(claims.aud) == "string" then
        aud_ok = claims.aud == conf.client_id
    elseif type(claims.aud) == "table" then
        for _, aud in ipairs(claims.aud) do
            if aud == conf.client_id then
                aud_ok = true
                break
            end
        end
    end
    if not aud_ok then
        return nil, "aud does not contain the client_id"
    end

    if type(claims.iat) ~= "number" then
        return nil, "iat claim is missing"
    end
    local now = ngx.time()
    if claims.iat < now - BCL_IAT_SLACK or claims.iat > now + BCL_IAT_SLACK then
        return nil, "iat is outside the acceptance window"
    end

    if type(claims.events) ~= "table"
       or type(claims.events[BCL_EVENT]) ~= "table" then
        return nil, "events claim does not contain the back-channel logout event"
    end

    if claims.nonce ~= nil then
        return nil, "nonce claim is prohibited in a logout token"
    end

    if type(claims.jti) ~= "string" or claims.jti == "" then
        return nil, "jti claim is missing"
    end

    if type(claims.sub) ~= "string" and type(claims.sid) ~= "string" then
        return nil, "either a sub or a sid claim is required"
    end

    return claims
end


local function bcl_error(description)
    return 400, core.json.encode({
        error = "invalid_request",
        error_description = description,
    })
end


-- The back-channel logout endpoint: an unauthenticated server-to-server
-- POST from the provider (Back-Channel Logout 1.0 section 2.5). Responses
-- per section 2.8: empty 200 on success, 400 with an RFC 6749-style JSON
-- error body otherwise, never cached. A store failure is a 400, not a 200:
-- claiming success while dropping the revocation would end the provider's
-- delivery attempts.
local function handle_backchannel_logout(conf)
    core.response.set_header("Cache-Control", "no-store")

    if ngx.req.get_method() ~= "POST" then
        return 405
    end

    ngx.req.read_body()
    local args = ngx.req.get_post_args()
    local logout_token = args and args.logout_token
    if type(logout_token) ~= "string" or logout_token == "" then
        return bcl_error("the logout_token parameter is missing")
    end

    local discovery, discovery_err = openidc.get_discovery_doc(conf)
    if discovery_err then
        core.log.error("OIDC backchannel logout discovery failed: ", discovery_err)
        return bcl_error("failed to load the discovery document")
    end

    local claims, validate_err =
        bcl_validate_logout_token(conf, discovery, logout_token)
    if not claims then
        core.log.warn("OIDC backchannel logout token rejected: ", validate_err)
        return bcl_error(validate_err)
    end

    local jti_key = "bcl:jti:" .. discovery.issuer .. "#" .. claims.jti
    local seen, store_err = bcl_store_get(conf, jti_key)
    if store_err then
        core.log.error("OIDC backchannel logout store failed: ", store_err)
        return bcl_error("the revocation store is unavailable")
    end
    if seen then
        core.log.warn("OIDC backchannel logout token rejected: ",
                      "a logout token with this jti was already received")
        return bcl_error("a logout token with this jti was already received")
    end
    local ok
    ok, store_err = bcl_store_set(conf, jti_key, BCL_JTI_TTL)
    if not ok then
        core.log.error("OIDC backchannel logout store failed: ", store_err)
        return bcl_error("the revocation store is unavailable")
    end

    -- Section 2.4: a token with a sid revokes that one session; a sub-only
    -- token revokes every session the user had when it was received
    -- (section 2.7).
    local key, logged_target
    if claims.sid then
        key = bcl_denylist_key("sid", conf, discovery.issuer, claims.sid)
        logged_target = "sid " .. claims.sid
    else
        key = bcl_denylist_key("sub", conf, discovery.issuer, claims.sub)
        logged_target = "sub " .. claims.sub
    end
    local ttl = (conf.session and conf.session.absolute_timeout)
                or BCL_DENYLIST_TTL
    ok, store_err = bcl_store_set(conf, key, ttl)
    if not ok then
        core.log.error("OIDC backchannel logout store failed: ", store_err)
        return bcl_error("the revocation store is unavailable")
    end

    core.log.warn("OIDC backchannel logout accepted for ", logged_target)
    return 200
end


-- Checks the session's identity against the revocation store. Returns true
-- (revoked), false (clean), or nil plus an error when the store cannot be
-- reached - no verdict is not a verdict.
local function session_revoked_by_backchannel_logout(conf, response, session)
    local id_token = response.id_token
    if not id_token then
        return false
    end

    if id_token.sid then
        local revoked_at, err = bcl_store_get(conf,
            bcl_denylist_key("sid", conf, id_token.iss, id_token.sid))
        if err then
            return nil, err
        end
        if revoked_at then
            return true
        end
    end

    if id_token.sub then
        local revoked_at, err = bcl_store_get(conf,
            bcl_denylist_key("sub", conf, id_token.iss, id_token.sub))
        if err then
            return nil, err
        end
        if revoked_at then
            -- A sub entry means "log out every session this user had when
            -- the logout was received": a session authenticated after it
            -- stays valid. A missing timestamp kills the session, erring
            -- toward revocation.
            local auth_at = session:get("last_authenticated")
                            or id_token.auth_time or id_token.iat
            if not auth_at or auth_at <= revoked_at then
                return true
            end
        end
    end

    return false
end


function _M.rewrite(plugin_conf, ctx)
    local conf = core.table.clone(plugin_conf)
    flatten_openidc_options(conf)

    -- Snapshot the client-supplied X-Access-Token (it doubles as a bearer
    -- input via get_bearer_access_token) and clear the five headers this
    -- plugin advertises as outputs so client-supplied values cannot bleed
    -- through to the upstream.
    ctx.openid_connect_client_x_access_token = core.request.header(ctx, "X-Access-Token")
    core.request.set_header(ctx, "X-Access-Token", nil)
    core.request.set_header(ctx, "X-Userinfo", nil)
    core.request.set_header(ctx, "X-ID-Token", nil)
    core.request.set_header(ctx, "X-Refresh-Token", nil)
    core.request.set_header(ctx, "X-Raw-ID-Token", nil)

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

    -- ctx.var.uri is deliberate: it is the path without the query string,
    -- so a provider that appends query parameters still reaches the endpoint.
    if conf.backchannel_logout and ctx.var.uri == conf.backchannel_logout.path then
        return handle_backchannel_logout(conf)
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

    local response, err, session

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

            -- jwt audience claim validator
            local audience_claim = core.table.try_read_attr(conf, "claim_validator",
                                                             "audience", "claim") or "aud"
            local audience_value = response[audience_claim]
            if core.table.try_read_attr(conf, "claim_validator", "audience", "required")
                and not audience_value then
                core.log.error("OIDC introspection failed: required audience (",
                                audience_claim, ") not present")
                local error_response = { error = "required audience claim not present" }
                return 403, core.json.encode(error_response)
            end
            if core.table.try_read_attr(conf, "claim_validator", "audience", "match_with_client_id")
                and audience_value ~= nil then
                local error_response = { error = "mismatched audience" }
                local matched = false
                if type(audience_value) == "table" then
                    for _, v in ipairs(audience_value) do
                        if conf.client_id == v then
                            matched = true
                        end
                    end
                    if not matched then
                        core.log.error("OIDC introspection failed: ",
                                        "audience list does not contain the client id")
                        return 403, core.json.encode(error_response)
                    end
                elseif conf.client_id ~= audience_value then
                    core.log.error("OIDC introspection failed: ",
                                    "audience does not match the client id")
                    return 403, core.json.encode(error_response)
                end
            end

            -- Validate bearer-path claims against claim_schema when configured.
            -- The schema is applied directly to the flat JWT payload / introspection
            -- response, which is different from the session-flow structure
            -- {user, access_token, id_token}.
            if conf.claim_schema then
                local ok, err = core.schema.check(conf.claim_schema, response)
                if not ok then
                    core.log.error("OIDC claim validation failed: ", err)
                    ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm ..
                        '", error="invalid_token", error_description="' .. err .. '"'
                    return ngx.HTTP_UNAUTHORIZED
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

        -- When set_raw_id_token_header is enabled and the user has explicitly restricted
        -- session_contents, ensure enc_id_token is included so session:get("enc_id_token")
        -- returns the raw signed JWT. When session_contents is nil, lua-resty-openidc stores
        -- all session data by default (including enc_id_token), so no action is needed.
        if conf.set_raw_id_token_header and conf.session_contents then
            conf.session_contents = core.table.clone(conf.session_contents)
            conf.session_contents.enc_id_token = true
        end

        -- Authenticate the request. This will validate the access token if it
        -- is stored in a sessions cookie, and also renew the token if required.
        -- If no token can be extracted, the response will redirect to the ID
        -- provider's authorization endpoint to initiate the Relying Party flow.
        -- This code path also handles when the ID provider then redirects to
        -- the configured redirect URI after successful authentication.
        local target_url
        response, err, target_url, session = openidc.authenticate(conf, nil, unauth_action,
                                                          build_session_opts(conf.session))

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

            -- Stale authorization callback: the session holds no authorization
            -- state for the state in the callback, e.g. an already completed
            -- callback was replayed, or the state was pruned after too many
            -- concurrent flows. (Concurrent logins in several tabs are handled
            -- by resty.openidc itself since 1.9.0, which keeps one
            -- authorization state per in-flight flow.) The client is a browser
            -- mid-navigation, so instead of a dead-end 500, send it back to the
            -- original URL that resty.openidc returns alongside the error: a
            -- fresh flow starts from there and completes without any user
            -- interaction while the ID provider still holds an SSO session.
            if err == STATE_MISMATCH_ERR and target_url
               and ngx.req.get_method() == "GET" then
                core.log.warn("OIDC state mismatch (replayed or pruned ",
                              "callback), restarting the authentication flow")
                core.response.set_header("Location", target_url)
                return 302
            end

            core.log.error("OIDC authentication failed: ", err)
            return 500
        end

        if response then
            if conf.backchannel_logout then
                local revoked, bcl_err =
                    session_revoked_by_backchannel_logout(conf, response, session)

                if bcl_err then
                    -- No verdict: fail the request but keep the session, so
                    -- a store hiccup neither forwards a possibly revoked
                    -- token nor logs the whole user base out.
                    core.log.error("OIDC backchannel logout store failed: ",
                                   bcl_err)
                    session:close()
                    return 503
                end

                if revoked then
                    core.log.warn("OIDC session revoked by backchannel logout")

                    -- Drop the dead session. Every branch below returns, so
                    -- the tail close() is never reached.
                    session:clear_request_cookie()
                    session:destroy()

                    if conf.unauth_action == "pass" then
                        return nil
                    end

                    if conf.unauth_action == "deny" then
                        return 401
                    end

                    -- Start a fresh code flow; on success authenticate()
                    -- redirects and does not return.
                    local _, auth_err, _, new_session =
                        openidc.authenticate(conf, nil, "auth",
                                             build_session_opts(conf.session))
                    if new_session then
                        new_session:close()
                    end

                    if auth_err then
                        core.log.error("OIDC re-authentication failed: ", auth_err)
                        return 500
                    end

                    return
                end
            end

            local ok, err = validate_claims_in_oidcauth_response(response, conf)
            if not ok then
                core.log.error("OIDC claim validation failed: ", err)
                ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm ..
                        '", error="invalid_token", error_description="' .. err .. '"'
                return ngx.HTTP_UNAUTHORIZED
            end
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
            local refresh_token = session:get("refresh_token")
            if refresh_token and conf.set_refresh_token_header then
                core.request.set_header(ctx, "X-Refresh-Token", refresh_token)
            end

            -- Add X-Raw-ID-Token header, maybe.
            local enc_id_token = session:get("enc_id_token")
            if enc_id_token and conf.set_raw_id_token_header then
                core.request.set_header(ctx, "X-Raw-ID-Token", enc_id_token)
            end
        end
    end
    if session then
        session:close()
    end
end


return _M
