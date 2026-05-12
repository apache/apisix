--
---- Licensed to the Apache Software Foundation (ASF) under one or more
---- contributor license agreements.  See the NOTICE file distributed with
---- this work for additional information regarding copyright ownership.
---- The ASF licenses this file to You under the Apache License, Version 2.0
---- (the "License"); you may not use this file except in compliance with
---- the License.  You may obtain a copy of the License at
----
----     http://www.apache.org/licenses/LICENSE-2.0
----
---- Unless required by applicable law or agreed to in writing, software
---- distributed under the License is distributed on an "AS IS" BASIS,
---- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
---- See the License for the specific language governing permissions and
---- limitations under the License.
----
local core = require("apisix.core")
local http = require("resty.http")
local openssl_mac = require("resty.openssl.mac")
local bit = require("bit")
local ngx = ngx
local ngx_re_match = ngx.re.match
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64

local CAS_REQUEST_URI = "CAS_REQUEST_URI"
local COOKIE_NAME = "CAS_SESSION"
local SESSION_LIFETIME = 3600
local STORE_NAME = "cas_sessions"

local store = ngx.shared[STORE_NAME]


local plugin_name = "cas-auth"
local schema = {
    type = "object",
    properties = {
        idp_uri = {type = "string"},
        cas_callback_uri = {type = "string"},
        logout_uri = {type = "string"},
        cookie = {
            type = "object",
            properties = {
                secret = {type = "string", minLength = 32},
                secure = {type = "boolean", default = true},
                samesite = {type = "string", enum = {"Lax", "None"}, default = "Lax"},
            },
            required = {"secret"},
        },
    },
    encrypt_fields = {"cookie.secret"},
    required = {
        "idp_uri", "cas_callback_uri", "logout_uri", "cookie"
    }
}

local _M = {
    version = 0.1,
    priority = 2597,
    name = plugin_name,
    schema = schema,
}

local function cookie_attrs(conf)
    -- core.schema.check() validates but does not apply JSONSchema defaults, so
    -- conf.cookie.secure/samesite may be nil at runtime. Default defensively.
    local secure = conf.cookie.secure ~= false
    local samesite = conf.cookie.samesite or "Lax"
    local attrs = "; Path=/; HttpOnly"
    if secure then
        attrs = attrs .. "; Secure"
    end
    attrs = attrs .. "; SameSite=" .. samesite
    return attrs
end

function _M.check_schema(conf)
    local check = {"idp_uri"}
    core.utils.check_https(check, conf, plugin_name)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.cookie.samesite == "None" and conf.cookie.secure == false then
        return false,
            "cookie.secure must be true when cookie.samesite is \"None\""
    end
    return true
end

local function uri_without_ticket(conf, ctx)
    return ctx.var.scheme .. "://" .. ctx.var.host .. ":" ..
        ctx.var.server_port .. conf.cas_callback_uri
end

local function get_session_id(ctx)
    return ctx.var["cookie_" .. COOKIE_NAME]
end

local function set_our_cookie(conf, name, val)
    core.response.add_header("Set-Cookie", name .. "=" .. val .. cookie_attrs(conf))
end

local function compute_hmac(secret, val)
    local m, err = openssl_mac.new(secret, "HMAC", nil, "sha256")
    if not m then return nil, err end
    return m:final(val)
end

local function eq_const_time(a, b)
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do
        diff = bit.bor(diff, bit.bxor(a:byte(i), b:byte(i)))
    end
    return diff == 0
end

local function sign_value(secret, val)
    local sig, err = compute_hmac(secret, val)
    if not sig then
        core.log.error("cas-auth: hmac sign failed: ", err)
        return nil
    end
    return ngx_encode_base64(val, true) .. "." .. ngx_encode_base64(sig, true)
end

local function verify_value(secret, signed)
    if not signed then return nil end
    local dot = signed:find(".", 1, true)
    if not dot then return nil end
    local val = ngx_decode_base64(signed:sub(1, dot - 1))
    local sig = ngx_decode_base64(signed:sub(dot + 1))
    if not val or not sig then return nil end
    local expected, err = compute_hmac(secret, val)
    if not expected then
        core.log.error("cas-auth: hmac verify failed: ", err)
        return nil
    end
    if not eq_const_time(sig, expected) then return nil end
    return val
end

local function is_safe_redirect(uri)
    if not uri or uri == "" then return false end
    if uri:sub(1, 1) ~= "/" then return false end
    if uri:sub(1, 2) == "//" then return false end
    if uri:find("\\", 1, true) then return false end
    if uri:find("[\r\n]") then return false end
    return true
end

-- Exposed for unit tests; not part of the plugin's public API.
_M._test_helpers = {
    sign_value = sign_value,
    verify_value = verify_value,
    is_safe_redirect = is_safe_redirect,
}

local function first_access(conf, ctx)
    local login_uri = conf.idp_uri .. "/login?" ..
        ngx.encode_args({ service = uri_without_ticket(conf, ctx) })
    core.log.info("cas-auth: redirecting unauthenticated request to IdP")
    local signed = sign_value(conf.cookie.secret, ctx.var.request_uri)
    if signed then
        set_our_cookie(conf, CAS_REQUEST_URI, signed)
    end
    core.response.set_header("Location", login_uri)
    return ngx.HTTP_MOVED_TEMPORARILY
end

local function with_session_id(conf, ctx, session_id)
    -- does the cookie exist in our store?
    local user = store:get(session_id)
    if user == nil then
        set_our_cookie(conf, COOKIE_NAME, "deleted; Max-Age=0")
        return first_access(conf, ctx)
    else
        -- refresh the TTL
        store:set(session_id, user, SESSION_LIFETIME)
        core.log.info("cas-auth: session refreshed")
    end
end

local function set_store_and_cookie(conf, session_id, user)
    -- place cookie into cookie store
    local success, err, forcible = store:add(session_id, user, SESSION_LIFETIME)
    if success then
        if forcible then
            core.log.info("CAS cookie store is out of memory")
        end
        set_our_cookie(conf, COOKIE_NAME, session_id)
    else
        if err == "no memory" then
            core.log.emerg("CAS cookie store is out of memory")
        elseif err == "exists" then
            core.log.error("Same CAS ticket validated twice, this should never happen!")
        else
            core.log.error("CAS cookie store: ", err)
        end
    end
    return success
end

local function validate(conf, ctx, ticket)
    -- send a request to CAS to validate the ticket
    local httpc = http.new()
    local res, err = httpc:request_uri(conf.idp_uri ..
        "/serviceValidate",
        { query = { ticket = ticket, service = uri_without_ticket(conf, ctx) } })

    if res and res.status == ngx.HTTP_OK and res.body ~= nil then
        if core.string.find(res.body, "<cas:authenticationSuccess>") then
            local m = ngx_re_match(res.body, "<cas:user>(.*?)</cas:user>", "jo")
            if m then
                return m[1]
            end
        else
            core.log.info("CAS serviceValidate did not return authenticationSuccess")
        end
    else
        core.log.error("validate ticket failed: status=", (res and res.status),
            ", has_body=", (res and res.body ~= nil or false), ", err=", err)
    end
    return nil
end

local function validate_with_cas(conf, ctx, ticket)
    local user = validate(conf, ctx, ticket)
    if user and set_store_and_cookie(conf, ticket, user) then
        local request_uri = verify_value(conf.cookie.secret,
            ctx.var["cookie_" .. CAS_REQUEST_URI])
        set_our_cookie(conf, CAS_REQUEST_URI, "deleted; Max-Age=0")
        if not is_safe_redirect(request_uri) then
            core.log.warn("cas-auth: rejected unsafe redirect target, falling back to /")
            request_uri = "/"
        end
        core.log.info("cas-auth: validation succeeded for user=", user)
        core.response.set_header("Location", request_uri)
        return ngx.HTTP_MOVED_TEMPORARILY
    else
        return ngx.HTTP_UNAUTHORIZED, {message = "invalid ticket"}
    end
end

local function logout(conf, ctx)
    local session_id = get_session_id(ctx)
    if session_id == nil then
        return ngx.HTTP_UNAUTHORIZED
    end

    core.log.info("cas-auth: logout invoked")
    store:delete(session_id)
    set_our_cookie(conf, COOKIE_NAME, "deleted; Max-Age=0")

    core.response.set_header("Location", conf.idp_uri .. "/logout")
    return ngx.HTTP_MOVED_TEMPORARILY
end

function _M.access(conf, ctx)
    local method = core.request.get_method()
    local uri = ctx.var.uri

    if method == "GET" and uri == conf.logout_uri then
        return logout(conf, ctx)
    end

    if method == "POST" and uri == conf.cas_callback_uri then
        local data = core.request.get_body()
        local ticket = data:match("<samlp:SessionIndex>(.*)</samlp:SessionIndex>")
        if ticket == nil then
            return ngx.HTTP_BAD_REQUEST,
                {message = "invalid logout request from IdP, no ticket"}
        end
        core.log.info("cas-auth: SLO request received from IdP")
        local session_id = ticket
        local user = store:get(session_id)
        if user then
            store:delete(session_id)
            core.log.info("cas-auth: SLO session deleted for user=", user)
        end
    else
        local session_id = get_session_id(ctx)
        if session_id ~= nil then
            return with_session_id(conf, ctx, session_id)
        end

        local ticket = ctx.var.arg_ticket
        if ticket ~= nil and uri == conf.cas_callback_uri then
            return validate_with_cas(conf, ctx, ticket)
        else
            return first_access(conf, ctx)
        end
    end
end

return _M
