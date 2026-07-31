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
local schema_def = require("apisix.schema_def")
local auth_utils = require("apisix.utils.auth")
local consumer_mod = require("apisix.consumer")
local ldap_client = require("resty.ldap.client")
local ldap_protocol = require("resty.ldap.protocol")
local ldap_filter = require("resty.ldap.filter")
local ngx = ngx
local ipairs = ipairs
local type = type
local ngx_decode_base64 = ngx.decode_base64
local ngx_re_match = ngx.re.match
local str_find = string.find
local str_sub = string.sub
local parse_addr = core.utils.parse_addr

-- RFC 4512 attribute-description: a descriptor ("cn", "sAMAccountName") or a
-- numeric OID ("1.2.840.113556.1.4.656"), either optionally followed by
-- ";option" suffixes ("cn;lang-en", "1.2.840.113556.1.4.656;binary").
local ATTR_PATTERN = "^(?:[A-Za-z][A-Za-z0-9-]*"
                     .. "|(?:0|[1-9][0-9]*)(?:\\.(?:0|[1-9][0-9]*))+)"
                     .. "(?:;[A-Za-z0-9-]+)*$"

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        -- connection
        ldap_uri     = { type = "string" },                        -- "host[:port]"
        use_ldaps    = { type = "boolean", default = false },
        use_starttls = { type = "boolean", default = false },
        ssl_verify   = { type = "boolean", default = true },
        timeout      = { type = "integer", minimum = 1, maximum = 60000,
                         default = 3000 },                          -- milliseconds

        -- connection pool
        keepalive           = { type = "boolean", default = true },
        keepalive_timeout   = { type = "integer", minimum = 1000, default = 60000 },
        keepalive_pool_size = { type = "integer", minimum = 1, default = 5 },
        keepalive_pool_name = { type = "string" },

        -- user resolution (search-then-bind)
        base_dn       = { type = "string" },                       -- search root
        attribute     = { type = "string",                         -- filter: (attribute=username)
                          default = "cn", pattern = ATTR_PATTERN },
        bind_dn       = { type = "string" },                       -- absent => anonymous search
        ldap_password = { type = "string" },

        -- search bounds
        size_limit = { type = "integer", minimum = 2, default = 2 },
        time_limit = { type = "integer", minimum = 0, default = 5 }, -- seconds; 0 = server default



        -- consumer
        consumer_required  = { type = "boolean", default = true },

        -- request handling
        header_type      = { type = "string", enum = {"ldap", "basic"}, default = "ldap" },
        realm            = schema_def.get_realm_schema("ldap"),

    },
    encrypt_fields = {"ldap_password"},
    required = {"ldap_uri", "base_dn"},
}

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        user_dn  = { type = "string" },
    },
    required = {"user_dn"},
}

local plugin_name = "ldap-auth-advanced"


local _M = {
    version = 0.1,
    priority = 2541,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.use_ldaps and conf.use_starttls then
        return false, "use_ldaps and use_starttls are mutually exclusive"
    end

    if conf.bind_dn and not conf.ldap_password then
        return false, "ldap_password is required when bind_dn is set"
    end

    -- ldap_uri may omit ":port"; the effective port (636 with use_ldaps,
    -- else 389) is resolved when the connection is opened.

    return true
end



-- Shared 401 helper for the authentication-failure paths.
local function auth_failed(conf, ctx, reason)

    -- under multi-auth, decline quietly and let the wrapper render the 401
    if auth_utils.is_running_under_multi_auth(ctx) then
        return 401
    end

    if reason then
        core.log.warn(plugin_name, ": ", reason)
    end
    core.response.set_header("WWW-Authenticate",
                             conf.header_type .. " realm=\"" .. conf.realm .. "\"")
    return 401, { message = "Authorization required" }
end




-- Parse one credential header value: the scheme word is conf.header_type
-- ("ldap" or "basic", case-insensitive), the payload is
-- base64("username:password").
local function parse_credential_header(conf, auth_header)
    local m, err = ngx_re_match(auth_header,
                                "^(?i:" .. conf.header_type .. ")\\s+(.+)", "jo")
    if err then
        return nil, nil, "error matching authorization header: " .. err
    end
    if not m then
        return nil, nil, "invalid authorization header format"
    end

    local decoded = ngx_decode_base64(m[1])
    if not decoded then
        return nil, nil, "failed to base64-decode authorization header"
    end

    -- split on the FIRST colon only: the password may itself contain ':'
    local sep = str_find(decoded, ":", 1, true)
    if not sep then
        return nil, nil, "invalid credential: missing ':' separator"
    end

    return str_sub(decoded, 1, sep - 1), str_sub(decoded, sep + 1)
end


-- Proxy-Authorization takes priority, but only when it parses into
-- credentials for conf.header_type: a forward proxy may spend that header
-- on its own credentials (e.g. "Basic ...") while the end user's ride in
-- Authorization, so its mere presence must not mask a usable Authorization.
local function extract_credentials(conf, ctx)
    local proxy_err
    local proxy_header = core.request.header(ctx, "Proxy-Authorization")
    if proxy_header then
        local username, password
        username, password, proxy_err = parse_credential_header(conf, proxy_header)
        if username then
            return username, password
        end
    end

    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return nil, nil, proxy_err or "missing authorization header"
    end

    return parse_credential_header(conf, auth_header)
end


-- resty.ldap reports a directory result-code failure as
-- "<op> failed, error: <ERROR_MSG[code]>, details: <diagnostic>"; anything
-- else is a socket/TLS/timeout error or a protocol violation. Match against
-- the library's own message table so the strings cannot drift from it.
local RESULT_INVALID_CREDENTIALS = ldap_protocol.ERROR_MSG[49]
local RESULT_SIZE_LIMIT_EXCEEDED = ldap_protocol.ERROR_MSG[4]

local function is_result_code(err, op, result_msg)
    if type(err) ~= "string" then
        return false
    end
    local prefix = op .. " failed, error: " .. result_msg .. ", details:"
    return str_sub(err, 1, #prefix) == prefix
end




-- The LDAP round trip: resolve the user DN and authenticate the user's bind
-- on ONE pinned connection. Returns (nil, nil, user_dn) on success, or
-- (code, body) on failure. The socket is closed on every failure path and
-- released to the pool only on success, so a poisoned socket is never pooled.
local function ldap_resolve(conf, ctx, username, password)
    -- The only client-controlled part of the search filter is the escaped
    -- username. filter.escape leaves bytes the filter grammar rejects (e.g.
    -- invalid UTF-8), and a grammar reject at search time would surface as a
    -- 500 -- misclassifying a bad credential as a server fault. Pre-compile
    -- the filter so any reject is a clean 401.
    local search_filter = "(" .. conf.attribute .. "="
                          .. ldap_filter.escape(username) .. ")"
    if not ldap_filter.compile(search_filter) then
        return auth_failed(conf, ctx, "invalid username")
    end

    -- ldap_uri is "host" or "host:port"; when the port is omitted it
    -- defaults to 636 under LDAPS, else 389.
    local host, port = parse_addr(conf.ldap_uri)
    if not port then
        port = conf.use_ldaps and 636 or 389
    end

    local client = ldap_client:new(host, port, {
        socket_timeout      = conf.timeout,
        keepalive_timeout   = conf.keepalive_timeout,
        keepalive_pool_size = conf.keepalive_pool_size,
        keepalive_pool_name = conf.keepalive_pool_name,
        start_tls           = conf.use_starttls,
        ldaps               = conf.use_ldaps,
        ssl_verify          = conf.ssl_verify,
    })

    -- Bind before every search: a pooled socket may arrive bound as a
    -- previous request's end user. Anonymous bind when bind_dn is unset.
    -- The client connects lazily on the first operation, so a socket/TLS
    -- failure surfaces here as (nil, err) -- an outage, never auth -- while
    -- a directory rejection is (false, err).
    local bind_ok, berr
    if conf.bind_dn then
        bind_ok, berr = client:simple_bind(conf.bind_dn, conf.ldap_password)
    else
        bind_ok, berr = client:simple_bind("", "")
    end
    if not bind_ok then
        client:close()
        if bind_ok == nil then
            core.log.error(plugin_name, ": LDAP connect failed: ", berr)
            return 500
        end
        -- a rejected search bind (e.g. a rotated service-account password)
        -- is a misconfiguration, never the client's auth failure
        core.log.error(plugin_name, ": LDAP search bind failed: ", berr)
        return 500
    end

    -- Search for the user. size_limit floors at 2 (schema minimum) so a 2nd
    -- match is observable.
    local entries, serr = client:search(
        conf.base_dn,
        ldap_protocol.SEARCH_SCOPE_WHOLE_SUBTREE,
        ldap_protocol.SEARCH_DEREF_ALIASES_ALWAYS,
        conf.size_limit, conf.time_limit,
        false,
        search_filter)
    if entries == false then
        client:close()
        if is_result_code(serr, "search", RESULT_SIZE_LIMIT_EXCEEDED) then
            -- more than size_limit entries matched the login attribute: the
            -- same ambiguity as match_count > 1 below; fail closed
            return auth_failed(conf, ctx,
                               "ambiguous user match (size limit exceeded); "
                               .. "check attribute uniqueness")
        end
        core.log.error(plugin_name, ": LDAP user search failed: ", serr)
        return 500
    end

    -- count SearchResultEntry rows (the library drops SearchResultDone)
    local user_dn
    local match_count = 0
    for _, entry in ipairs(entries) do
        if entry.entry_dn then
            match_count = match_count + 1
            user_dn = entry.entry_dn
        end
    end
    if match_count == 0 then
        client:close()
        return auth_failed(conf, ctx, "user not found")
    end
    if match_count > 1 then
        -- the login attribute is not unique under base_dn: a directory
        -- misconfiguration. Fail closed rather than bind an arbitrary entry.
        client:close()
        return auth_failed(conf, ctx,
                           "ambiguous user match (>1 entry); check attribute uniqueness")
    end

    -- Authenticate: bind as the resolved user. invalidCredentials is a wrong
    -- password (401); any other result code (busy, unavailable, ...) or a
    -- transport error is an outage (500).
    local auth_ok, aerr = client:simple_bind(user_dn, password)
    if not auth_ok then
        client:close()
        if is_result_code(aerr, "simple bind", RESULT_INVALID_CREDENTIALS) then
            return auth_failed(conf, ctx, "user authentication failed")
        end
        core.log.error(plugin_name, ": LDAP authentication bind failed: ", aerr)
        return 500
    end


    if conf.keepalive == false then
        client:close()
    else
        client:set_keepalive()
    end

    return nil, nil, user_dn
end


function _M.rewrite(conf, ctx)
    -- Strip the client-supplied identity headers before any auth work: only
    -- attach_consumer() may set them, and with consumer_required=false it
    -- never runs, so an inbound value would otherwise pass through untouched.
    core.request.set_header(ctx, "X-Authenticated-Groups", nil)
    core.request.set_header(ctx, "X-Consumer-Username", nil)
    core.request.set_header(ctx, "X-Credential-Identifier", nil)
    core.request.set_header(ctx, "X-Consumer-Custom-ID", nil)

    local username, password, err = extract_credentials(conf, ctx)
    if err then
        return auth_failed(conf, ctx, err)
    end

    -- A zero-length password would be an RFC 4513 5.1.2 unauthenticated bind,
    -- which authenticates anyone whose username resolves. Reject before any
    -- bind can be attempted.
    if password == "" then
        return auth_failed(conf, ctx, "empty password rejected before bind")
    end

    if username == "" then
        return auth_failed(conf, ctx, "empty username")
    end

    local code, body, user_dn = ldap_resolve(conf, ctx, username, password)
    if code then
        return code, body
    end

    -- Associate a Consumer with the authenticated identity, unless
    -- consumer_required is false. find_consumer() resolves secret references
    -- in the Consumer's user_dn and skips unresolved ones fail-closed.
    if conf.consumer_required ~= false then
        local consumer, consumer_conf, err =
            consumer_mod.find_consumer(plugin_name, "user_dn", user_dn)
        if err then
            return auth_failed(conf, ctx, "consumer_required but no Consumer is configured")
        end
        if not consumer then
            return auth_failed(conf, ctx,
                               "no Consumer maps to the authenticated user_dn")
        end

        consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    end
end

return _M
