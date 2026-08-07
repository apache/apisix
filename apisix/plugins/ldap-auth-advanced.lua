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
local secret = require("apisix.secret")
local ldap_client = require("resty.ldap.client")
local ldap_protocol = require("resty.ldap.protocol")
local ldap_filter = require("resty.ldap.filter")
local ngx = ngx
local ipairs = ipairs
local pairs = pairs
local type = type
local tonumber = tonumber
local ngx_decode_base64 = ngx.decode_base64
local ngx_re_match = ngx.re.match
local ngx_re_gsub = ngx.re.gsub
local str_byte = string.byte
local str_char = string.char
local str_find = string.find
local str_gsub = string.gsub
local str_lower = string.lower
local str_sub = string.sub
local table_concat = table.concat
local table_sort = table.sort
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
        ldap_uri     = { type = "string",                          -- "host[:port]"
                         minLength = 1, maxLength = 256 },
        use_ldaps    = { type = "boolean", default = false },
        use_starttls = { type = "boolean", default = false },
        ssl_verify   = { type = "boolean", default = true },
        timeout      = { type = "integer", minimum = 1, maximum = 60000,
                         default = 10000 },                         -- milliseconds

        -- connection pool
        keepalive           = { type = "boolean", default = true },
        keepalive_timeout   = { type = "integer", minimum = 1000, default = 60000 },
        keepalive_pool_size = { type = "integer", minimum = 1, default = 5 },
        keepalive_pool_name = { type = "string", minLength = 1, maxLength = 256 },

        -- user resolution (search-then-bind)
        base_dn       = { type = "string",                         -- search root
                          minLength = 1, maxLength = 4096 },
        attribute     = { type = "string", maxLength = 256,        -- filter: (attribute=username)
                          default = "cn", pattern = ATTR_PATTERN },
        bind_dn       = { type = "string",                         -- absent => anonymous search
                          minLength = 1, maxLength = 4096 },
        ldap_password = { type = "string", minLength = 1, maxLength = 4096 },

        -- search bounds
        size_limit = { type = "integer", minimum = 2, default = 2 },
        time_limit = { type = "integer", minimum = 0, default = 5 }, -- seconds; 0 = server default

        -- groups
        group_base_dn = { type = "string",                  -- absent => memberOf attribute path
                          minLength = 1, maxLength = 4096 },
        group_name_attribute = { type = "string", maxLength = 256,
                                 default = "cn", pattern = ATTR_PATTERN },
        group_member_attribute = { type = "string", maxLength = 256,
                                   default = "member", pattern = ATTR_PATTERN },
        user_membership_attribute = { type = "string", maxLength = 256,
                                      default = "memberOf",
                                      pattern = ATTR_PATTERN },

        -- authorization: outer array ORs, inner array ANDs
        groups_required = {
            type = "array", minItems = 1,
            items = { type = "array", minItems = 1,
                      items = { type = "string",
                                minLength = 1, maxLength = 4096 } },
        },

        -- consumer
        consumer_required  = { type = "boolean", default = true },

        -- request handling
        header_type      = { type = "string", enum = {"ldap", "basic"}, default = "ldap" },
        realm            = schema_def.get_realm_schema("ldap"),
        set_groups_header = {
            description = "Whether the collected group names should be added in the "
                .. "X-Authenticated-Groups header to the request for downstream.",
            type = "boolean", default = true },

    },
    encrypt_fields = {"ldap_password"},
    required = {"ldap_uri", "base_dn"},
}

local GROUP_NAME_DEFAULT = schema.properties.group_name_attribute.default
local GROUP_MEMBER_DEFAULT = schema.properties.group_member_attribute.default

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        user_dn  = { type = "string", minLength = 1, maxLength = 4096 },
        -- one group DN, or several that must ALL contain the user
        group_dn = {
            oneOf = {
                { type = "string", minLength = 1, maxLength = 4096 },
                { type = "array", minItems = 1, uniqueItems = true,
                  items = { type = "string", minLength = 1, maxLength = 4096 } },
            },
        },
    },
    -- exactly one association key: both set matches both branches, neither
    -- matches none -- either way oneOf rejects
    oneOf = {
        { required = {"user_dn"} },
        { required = {"group_dn"} },
    },
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

    -- Compared against the schema default, not presence: jsonschema injects
    -- defaults into conf, and stored config is re-validated on every reload.
    if not conf.group_base_dn then
        if conf.group_name_attribute ~= GROUP_NAME_DEFAULT then
            return false, "group_name_attribute is only used with group_base_dn"
        end
        if conf.group_member_attribute ~= GROUP_MEMBER_DEFAULT then
            return false, "group_member_attribute is only used with group_base_dn"
        end
    end

    -- ldap_uri may omit ":port"; the effective port (636 with use_ldaps,
    -- else 389) is resolved when the connection is opened.

    return true
end


local CHALLENGE_SCHEME = {
    ldap  = "ldap",
    basic = "Basic",
}


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
                             CHALLENGE_SCHEME[conf.header_type]
                             .. " realm=\"" .. conf.realm .. "\"")
    return 401, { message = "Authorization required" }
end


-- groups_required is an outer OR of inner ANDs, matched against the collected
-- group names verbatim (no case folding, no trimming).
local function groups_satisfied(groups_required, groups)
    local have = {}
    for i = 1, #groups do
        have[groups[i].name] = true
    end
    for _, inner in ipairs(groups_required) do
        local all = true
        for _, name in ipairs(inner) do
            if not have[name] then
                all = false
                break
            end
        end
        if all then
            return true
        end
    end
    return false
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

    local username = str_sub(decoded, 1, sep - 1)
    local password = str_sub(decoded, sep + 1)

    if password == "" then
        return nil, nil, "empty password rejected before bind"
    end
    if username == "" then
        return nil, nil, "empty username"
    end

    return username, password
end


-- Proxy-Authorization takes priority, but only when it parses into usable
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


-- Attribute lookup with a case-insensitive fallback: the server may echo the
-- requested descriptor in a different case.
local function attr_values(attributes, name)
    if not attributes then
        return nil
    end
    local vals = attributes[name]
    if vals then
        return vals
    end
    local lname = str_lower(name)
    for k, v in pairs(attributes) do
        if str_lower(k) == lname then
            return v
        end
    end
    return nil
end


-- Reverse RFC 4514 RDN-value escaping ("\2C" or "\," -> the literal char) so
-- group names taken from a DN match the unescaped attribute values byte for
-- byte. Single pass, hex escape first, so "\\2C" stays a backslash plus the
-- literal "2C"; a lone trailing backslash is kept as-is.
local function unescape_rdn_value(v)
    if not str_find(v, "\\", 1, true) then
        return v
    end
    return (ngx_re_gsub(v, [[\\([0-9A-Fa-f]{2}|.)]], function(m)
        local esc = m[1]
        return #esc == 2 and str_char(tonumber(esc, 16)) or esc
    end, "jos"))
end


-- The value of a DN's first RDN, unescaped, e.g.
-- "cn=Domain Admins,ou=groups,..." -> "Domain Admins".
local function first_rdn_value(dn)
    local eq = str_find(dn, "=", 1, true)
    if not eq then
        return dn
    end
    local i = eq + 1
    local n = #dn
    while i <= n do
        local b = str_byte(dn, i)
        if b == 92 then           -- '\' escapes the next byte
            i = i + 2
        elseif b == 44 then       -- ',' ends the first RDN
            return unescape_rdn_value(str_sub(dn, eq + 1, i - 1))
        else
            i = i + 1
        end
    end
    return unescape_rdn_value(str_sub(dn, eq + 1))
end


-- Map group search entries to {dn, name} pairs; when an entry did not carry
-- the name attribute, fall back to its DN's first RDN value.
local function collect_search_groups(entries, name_attr)
    local groups = {}
    for _, entry in ipairs(entries) do
        if entry.entry_dn then
            local vals = attr_values(entry.attributes, name_attr)
            groups[#groups + 1] = {
                dn = entry.entry_dn,
                name = (vals and vals[1]) or first_rdn_value(entry.entry_dn),
            }
        end
    end
    return groups
end


-- Each membership-attribute value on the user entry is a group DN; its name
-- is the DN's first RDN value. No extra LDAP round trip.
local function collect_membership_groups(user_entry, member_attr)
    local groups = {}
    local vals = attr_values(user_entry.attributes, member_attr)
    if vals then
        for _, dn in ipairs(vals) do
            groups[#groups + 1] = { dn = dn, name = first_rdn_value(dn) }
        end
    end
    return groups
end


-- Strip CR/LF and other control bytes from a directory-sourced value before
-- it is written into an upstream header (header-injection defense). Group
-- matching always uses the raw name, never this sanitized copy.
local function sanitize_header_value(v)
    return (str_gsub(v, "[%z\1-\31\127]", ""))
end


-- Returns the client's own (ok, err): false is a directory rejection, nil is
-- a transport failure.
local function bind_as_service(client, conf)
    if conf.bind_dn then
        return client:simple_bind(conf.bind_dn, conf.ldap_password)
    end
    return client:simple_bind("", "")
end


-- One index per consumer-config version: user_dn consumers hash by DN;
-- group_dn consumers are pre-sorted so the request-time scan realizes the
-- documented order -- walk the user's groups alphabetically, a consumer
-- ranks at its alphabetically-smallest group_dn, a larger group_dn set
-- (more specific) wins the same slot, the consumer name breaks exact ties.
-- Secrets resolve here, fail-closed, mirroring create_consume_cache.
local function build_consumer_index(consumer_conf)
    local index = { by_user_dn = {}, group_list = {} }
    for _, consumer in ipairs(consumer_conf.nodes) do
        local c = core.table.clone(consumer)
        c.auth_conf = secret.fetch_secrets(c.auth_conf, false)
        if not c.auth_conf or secret.has_secret_ref(c.auth_conf) then
            core.log.error(plugin_name, ": failed to resolve secret reference ",
                           "in consumer auth credential, skipping consumer: ",
                           c.consumer_name)
        elseif c.auth_conf.user_dn ~= nil then
            index.by_user_dn[c.auth_conf.user_dn] = c
        elseif c.auth_conf.group_dn ~= nil then
            local group_dns = c.auth_conf.group_dn
            if type(group_dns) == "string" then
                group_dns = { group_dns }
            else
                group_dns = core.table.clone(group_dns)
            end
            table_sort(group_dns)
            index.group_list[#index.group_list + 1] = {
                consumer = c,
                group_dns = group_dns,
            }
        else
            core.log.error(plugin_name, ": consumer has neither user_dn nor ",
                           "group_dn, skipping consumer: ", c.consumer_name)
        end
    end

    table_sort(index.group_list, function(a, b)
        if a.group_dns[1] ~= b.group_dns[1] then
            return a.group_dns[1] < b.group_dns[1]
        end
        if #a.group_dns ~= #b.group_dns then
            return #a.group_dns > #b.group_dns
        end
        return a.consumer.consumer_name < b.consumer.consumer_name
    end)

    return index
end


local index_cache = core.lrucache.new({ ttl = 300, count = 16 })

-- Two-phase Consumer resolution: the exact user_dn binding is the most
-- specific and always wins; group_dn consumers are consulted only when it
-- misses. Returns (consumer, consumer_conf) or (nil, nil, err) when no
-- Consumer carries this plugin at all.
local function find_ldap_consumer(user_dn, groups)
    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return nil, nil, "Missing related consumer"
    end

    local index = index_cache(plugin_name .. "#consumer_index",
                              consumer_conf.conf_version,
                              build_consumer_index, consumer_conf)

    local consumer = index.by_user_dn[user_dn]
    if consumer then
        return consumer, consumer_conf
    end

    if #index.group_list == 0 or #groups == 0 then
        return nil, consumer_conf
    end

    local have = {}
    for i = 1, #groups do
        have[groups[i].dn] = true
    end

    local chosen, matched
    for _, entry in ipairs(index.group_list) do
        local eligible = true
        for _, dn in ipairs(entry.group_dns) do
            if not have[dn] then
                eligible = false
                break
            end
        end
        if eligible then
            chosen = chosen or entry.consumer
            matched = matched or {}
            matched[#matched + 1] = entry.consumer.consumer_name
        end
    end

    if matched and #matched > 1 then
        core.log.warn(plugin_name, ": multiple consumers matched by group_dn (",
                      table_concat(matched, ", "), "); picked ", matched[1],
                      "; unintended consumers may have been matched")
    end

    return chosen, consumer_conf
end


-- The LDAP round trip: resolve the user DN and authenticate the user's bind,
-- then collect groups, on ONE pinned connection. Returns
-- (nil, nil, user_dn, groups) on success, or (code, body) on failure. The
-- socket is closed on every failure path and released to the pool only on
-- success, so a poisoned socket is never pooled.
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
    local bind_ok, berr = bind_as_service(client, conf)
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

    -- Search for the user. On the memberOf path, request
    -- user_membership_attribute so groups can be read off this same entry
    -- with no extra round trip; on the group-search path the entry's
    -- attributes are unused, so request none ("1.1", RFC 4511) -- an AD
    -- user's memberOf can be tens of KB that would be decoded and dropped.
    -- size_limit floors at 2 (schema minimum) so a 2nd match is observable.
    local entries, serr = client:search(
        conf.base_dn,
        ldap_protocol.SEARCH_SCOPE_WHOLE_SUBTREE,
        ldap_protocol.SEARCH_DEREF_ALIASES_ALWAYS,
        conf.size_limit, conf.time_limit,
        false,
        search_filter,
        { conf.group_base_dn and "1.1" or conf.user_membership_attribute })
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
    local user_entry
    local match_count = 0
    for _, entry in ipairs(entries) do
        if entry.entry_dn then
            match_count = match_count + 1
            user_entry = entry
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
    local user_dn = user_entry.entry_dn

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

    local groups
    if conf.group_base_dn then
        -- Currently bound as the END USER. Re-bind as the configured identity
        -- so the group search never runs under the caller. The extra round
        -- trip is deliberate: searching groups before the auth bind would
        -- avoid it, but then every wrong-password request would still incur
        -- a group search.
        local rb_ok, rberr = bind_as_service(client, conf)
        if not rb_ok then
            client:close()
            core.log.error(plugin_name, ": LDAP group-search re-bind failed: ",
                           rberr)
            return 500
        end

        local group_filter = "(" .. conf.group_member_attribute .. "="
                             .. ldap_filter.escape(user_dn) .. ")"
        -- sizeLimit is deliberately 0 (not conf.size_limit) so a user's
        -- groups are never silently truncated.
        local gentries, gerr = client:search(
            conf.group_base_dn,
            ldap_protocol.SEARCH_SCOPE_WHOLE_SUBTREE,
            ldap_protocol.SEARCH_DEREF_ALIASES_ALWAYS,
            0, conf.time_limit,
            false,
            group_filter,
            { conf.group_name_attribute })
        if gentries == false then
            -- already authenticated: unlike the user search, any failure here
            -- (sizeLimitExceeded included) is operational, never a 401
            client:close()
            core.log.error(plugin_name, ": LDAP group search failed: ", gerr)
            return 500
        end
        groups = collect_search_groups(gentries, conf.group_name_attribute)
    else
        groups = collect_membership_groups(user_entry,
                                           conf.user_membership_attribute)
    end

    if conf.keepalive == false then
        client:close()
    else
        client:set_keepalive()
    end

    return nil, nil, user_dn, groups
end


function _M.rewrite(conf, ctx)
    -- Strip the client-supplied identity headers before any auth work: only
    -- attach_consumer() sets X-Consumer-*, and only the success-path export
    -- below sets X-Authenticated-Groups; either can be skipped (consumer_
    -- required=false, set_groups_header=false), so an inbound value would
    -- otherwise pass through untouched.
    core.request.set_header(ctx, "X-Authenticated-Groups", nil)
    core.request.set_header(ctx, "X-Consumer-Username", nil)
    core.request.set_header(ctx, "X-Credential-Identifier", nil)
    core.request.set_header(ctx, "X-Consumer-Custom-ID", nil)

    -- Both fields are guaranteed non-empty: parse_credential_header rejects
    -- an empty username or password as an unusable credential.
    local username, password, err = extract_credentials(conf, ctx)
    if err then
        return auth_failed(conf, ctx, err)
    end

    local code, body, user_dn, groups = ldap_resolve(conf, ctx, username, password)
    if code then
        return code, body
    end

    -- an already-authenticated user failing authorization gets a real 403,
    -- never a 401; the warn names the denied user because no identity
    -- has been exported yet on this path
    if conf.groups_required and not groups_satisfied(conf.groups_required, groups) then
        core.log.warn(plugin_name, ": groups_required not satisfied for ", user_dn)
        return 403, { message = "Forbidden" }
    end

    -- Associate a Consumer with the authenticated identity, unless
    -- consumer_required is false. find_ldap_consumer() is the two-phase
    -- lookup: an exact user_dn binding always wins, group_dn consumers are
    -- consulted only when it misses. Either way, secret references in the
    -- Consumer's auth credential are resolved fail-closed (unresolved ones
    -- are skipped, never matched verbatim).
    if conf.consumer_required ~= false then
        local consumer, consumer_conf, err = find_ldap_consumer(user_dn, groups)
        if err then
            return auth_failed(conf, ctx, "consumer_required but no Consumer is configured")
        end
        if not consumer then
            return auth_failed(conf, ctx,
                               "no Consumer maps to the authenticated user_dn")
        end

        consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    end

    -- Reached only after every auth decision passed, so the header is absent
    -- on all 401/500 paths. The inbound strip above stays unconditional.
    if conf.set_groups_header and #groups > 0 then
        local names = {}
        for i = 1, #groups do
            names[i] = sanitize_header_value(groups[i].name)
        end
        core.request.set_header(ctx, "X-Authenticated-Groups",
                                table_concat(names, ","))
    end
end

return _M
