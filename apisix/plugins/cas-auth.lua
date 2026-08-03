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
local resty_sha256 = require("resty.sha256")
local resty_string = require("resty.string")
local bit = require("bit")
local ngx = ngx
local ngx_re_match = ngx.re.match
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64

local CAS_REQUEST_URI = "CAS_REQUEST_URI"
local COOKIE_PREFIX = "CAS_SESSION_"
local ENTRY_SEP = "|"
local SESSION_LIFETIME = 3600
local STORE_NAME = "cas_sessions"

local store = ngx.shared[STORE_NAME]

local session_opts_cache = {}


local plugin_name = "cas-auth"
local schema = {
    type = "object",
    properties = {
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum request body size in bytes buffered into "
                       .. "memory; larger request bodies are rejected",
        },
        idp_uri = {type = "string"},
        cas_callback_uri = {
            type = "string",
            description = "CAS callback location. Either a relative path " ..
                "(the CAS service URL is then built from the request scheme/host/port) " ..
                "or an absolute URL (e.g. https://app.example.com/cas_callback), " ..
                "which is used verbatim as the CAS service URL.",
        },
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

local function is_absolute_callback(cas_callback_uri)
    return cas_callback_uri:find("^https?://") ~= nil
end

-- Path component of cas_callback_uri, used to match against ctx.var.uri
-- (which is always a path). For an absolute URL the scheme://authority
-- prefix and any query/fragment are stripped; an absolute URL with no
-- path resolves to "/".
local function callback_path(cas_callback_uri)
    if not is_absolute_callback(cas_callback_uri) then
        return cas_callback_uri
    end
    local path = cas_callback_uri:gsub("^https?://[^/]+", "")
    path = path:gsub("[?#].*$", "")
    if path == "" then
        return "/"
    end
    return path
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.cookie.samesite == "None" and conf.cookie.secure == false then
        return false,
            "cookie.secure must be true when cookie.samesite is \"None\""
    end

    local check = {"idp_uri"}
    if is_absolute_callback(conf.cas_callback_uri) then
        core.table.insert(check, "cas_callback_uri")
    else
        core.log.warn("cas-auth: cas_callback_uri is a relative path; the CAS ",
            "service URL will be derived from the request Host header. ",
            "Configure an absolute cas_callback_uri to avoid relying on it.")
    end
    core.utils.check_https(check, conf, plugin_name)

    return true
end

local function uri_without_ticket(conf, ctx)
    if is_absolute_callback(conf.cas_callback_uri) then
        return conf.cas_callback_uri
    end
    return ctx.var.scheme .. "://" .. ctx.var.host .. ":" ..
        ctx.var.server_port .. conf.cas_callback_uri
end

-- Derive per-route cookie name and session-payload fingerprint from the
-- fields that define a CAS trust context (idp_uri + cas_callback_uri).
-- Memoised so the SHA-256 only runs once per distinct configuration.
local function session_opts(conf)
    local fp_input = conf.idp_uri .. ENTRY_SEP .. conf.cas_callback_uri
    local cached = session_opts_cache[fp_input]
    if cached then
        return cached
    end
    local sha256 = resty_sha256:new()
    sha256:update(fp_input)
    local digest_hex = resty_string.to_hex(sha256:final())
    cached = {
        cookie_name = COOKIE_PREFIX .. digest_hex,
        fingerprint = digest_hex,
    }
    session_opts_cache[fp_input] = cached
    return cached
end

local function pack_entry(fingerprint, user)
    return fingerprint .. ENTRY_SEP .. user
end

-- Returns (fingerprint, user) for entries written by pack_entry, or
-- (nil, nil) for legacy entries that pre-date per-config binding.
local function unpack_entry(entry)
    if not entry then return nil, nil end
    local sep = entry:find(ENTRY_SEP, 1, true)
    if not sep then return nil, nil end
    return entry:sub(1, sep - 1), entry:sub(sep + 1)
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
    callback_path = callback_path,
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

local function with_session_id(conf, ctx, opts, session_id)
    -- Namespacing the store key with the per-config fingerprint keeps
    -- ticket strings from different IdPs from colliding in cas_sessions.
    local key = opts.fingerprint .. ":" .. session_id
    local entry = store:get(key)
    if entry == nil then
        set_our_cookie(conf, opts.cookie_name, "deleted; Max-Age=0")
        return first_access(conf, ctx)
    end

    local stored_fp = unpack_entry(entry)
    if stored_fp ~= opts.fingerprint then
        -- session was issued under a different CAS configuration; do not honour
        set_our_cookie(conf, opts.cookie_name, "deleted; Max-Age=0")
        return first_access(conf, ctx)
    end

    local ok, err, forcible = store:set(key, entry, SESSION_LIFETIME)
    if not ok then
        core.log.error("cas-auth: failed to refresh session ttl: ", err or "unknown")
        return
    end
    if forcible then
        core.log.warn("cas-auth: session refresh caused forcible eviction")
    end
    core.log.info("cas-auth: session refreshed")
end

local function set_store_and_cookie(conf, opts, session_id, user)
    local entry = pack_entry(opts.fingerprint, user)
    local key = opts.fingerprint .. ":" .. session_id
    local success, err, forcible = store:add(key, entry, SESSION_LIFETIME)
    if success then
        if forcible then
            core.log.info("CAS cookie store is out of memory")
        end
        set_our_cookie(conf, opts.cookie_name, session_id)
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
    local request_uri = verify_value(conf.cookie.secret,
        ctx.var["cookie_" .. CAS_REQUEST_URI])
    if not request_uri or not is_safe_redirect(request_uri) then
        core.log.warn("cas-auth: callback rejected, missing or invalid initiation cookie")
        return ngx.HTTP_UNAUTHORIZED, {message = "invalid callback state"}
    end

    local user = validate(conf, ctx, ticket)
    local opts = session_opts(conf)
    if user and set_store_and_cookie(conf, opts, ticket, user) then
        set_our_cookie(conf, CAS_REQUEST_URI, "deleted; Max-Age=0")
        core.log.info("cas-auth: validation succeeded for user=", user)
        core.response.set_header("Location", request_uri)
        return ngx.HTTP_MOVED_TEMPORARILY
    end
    return ngx.HTTP_UNAUTHORIZED, {message = "invalid ticket"}
end

local function logout(conf, ctx)
    local opts = session_opts(conf)
    local session_id = ctx.var["cookie_" .. opts.cookie_name]
    if session_id == nil then
        return ngx.HTTP_UNAUTHORIZED
    end

    core.log.info("cas-auth: logout invoked")
    store:delete(opts.fingerprint .. ":" .. session_id)
    set_our_cookie(conf, opts.cookie_name, "deleted; Max-Age=0")

    core.response.set_header("Location", conf.idp_uri .. "/logout")
    return ngx.HTTP_MOVED_TEMPORARILY
end

function _M.access(conf, ctx)
    local method = core.request.get_method()
    local uri = ctx.var.uri
    local cas_callback_path = callback_path(conf.cas_callback_uri)

    if method == "GET" and uri == conf.logout_uri then
        return logout(conf, ctx)
    end

    if method == "POST" and uri == cas_callback_path then
        local data = core.request.get_body(conf.max_req_body_size)
        local ticket = data and data:match("<samlp:SessionIndex>(.+)</samlp:SessionIndex>")
        if ticket == nil then
            return ngx.HTTP_BAD_REQUEST,
                {message = "invalid logout request from IdP, no ticket"}
        end
        core.log.info("cas-auth: SLO request received from IdP")
        local opts = session_opts(conf)
        local key = opts.fingerprint .. ":" .. ticket
        local entry = store:get(key)
        if entry then
            store:delete(key)
            local _, user = unpack_entry(entry)
            core.log.info("cas-auth: SLO session deleted for user=", user or "<unknown>")
        end
        -- SLO callback ends here; never proxy the IdP's logout POST upstream
        return ngx.HTTP_OK
    else
        local opts = session_opts(conf)
        local session_id = ctx.var["cookie_" .. opts.cookie_name]
        if session_id ~= nil then
            return with_session_id(conf, ctx, opts, session_id)
        end

        local ticket = ctx.var.arg_ticket
        if ticket ~= nil and uri == cas_callback_path then
            return validate_with_cas(conf, ctx, ticket)
        else
            return first_access(conf, ctx)
        end
    end
end

return _M
