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

local ipairs   = ipairs
local core     = require("apisix.core")
local http     = require("resty.http")
local lrucache = require("resty.lrucache")
local pairs    = pairs
local type     = type
local tostring = tostring
local tonumber = tonumber
local concat   = table.concat
local find     = string.find
local lower    = string.lower
local match    = string.match
local md5      = ngx.md5

local plugin_ctx_id = core.lrucache.plugin_ctx_id

-- edge cache of auth decisions, shared across all routes on this worker;
-- entries are namespaced per plugin conf and identity, so no cross-route bleed
local auth_cache = lrucache.new(4096)

local schema = {
    type = "object",
    properties = {
        uri = {type = "string"},
        allow_degradation = {type = "boolean", default = false},
        status_on_error = {type = "integer", minimum = 200, maximum = 599, default = 403},
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        request_method = {
            type = "string",
            default = "GET",
            enum = {"GET", "POST"},
            description = "the method for client to request the authorization service"
        },
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum request body size in bytes buffered and "
                        .. "forwarded to the authorization service when "
                        .. "request_method is POST"
        },
        request_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "client request header that will be sent to the authorization service"
        },
        extra_headers = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                ["^[^:]+$"] = {
                    type = "string",
                    description = "header value as a string; may contain variables"
                                  .. "like $remote_addr, $request_uri"
                }
            },
            description = "extra headers sent to the authorization service; "
                        .. "values must be strings and can include variables"
                        .. "like $remote_addr, $request_uri."
        },
        upstream_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "authorization response header that will be sent to the upstream"
        },
        client_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "authorization response header that will be sent to"
                           .. "the client when authorizing failed"
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
        cache = {
            type = "object",
            properties = {
                ttl = {
                    type = "integer",
                    minimum = 1,
                    maximum = 3600,
                    default = 5,
                    description = "how long, in seconds, an auth decision is cached at the edge"
                },
                key_headers = {
                    type = "array",
                    minItems = 1,
                    items = {type = "string"},
                    description = "client request headers whose values identify the caller; "
                                .. "the auth decision is cached per unique combination of their "
                                .. "values, so this must cover every token/header the auth "
                                .. "service uses to decide"
                },
                include_method = {
                    type = "boolean",
                    default = false,
                    description = "include the client request method in the cache key"
                },
                include_uri = {
                    type = "boolean",
                    default = false,
                    description = "include the client request URI in the cache key"
                },
            },
            required = {"key_headers"},
            description = "opt-in caching of auth decisions at the edge (per worker) to cut "
                        .. "calls to the authorization service"
        },
    },
    required = {"uri"}
}


local _M = {
    version = 0.1,
    priority = 2002,
    name = "forward-auth",
    schema = schema,
}


function _M.check_schema(conf)
    local check = {"uri"}
    core.utils.check_https(check, conf, _M.name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, _M.name)

    return core.schema.check(schema, conf)
end


-- build a per-conf, per-identity cache key. plugin_ctx_id namespaces it by
-- conf id and version, so config edits invalidate the cache automatically.
local function build_cache_key(conf, ctx, body)
    local cache = conf.cache
    local parts = {}
    local n = 0
    for _, header in ipairs(cache.key_headers) do
        n = n + 1
        parts[n] = header
        n = n + 1
        -- NUL can never appear in a header value, so it is a safe delimiter
        parts[n] = core.request.header(ctx, header) or ""
    end
    if cache.include_method then
        n = n + 1
        parts[n] = "m:" .. core.request.get_method()
    end
    if cache.include_uri then
        n = n + 1
        parts[n] = "u:" .. ctx.var.request_uri
    end
    -- the forwarded body is an input to the decision, so key on it too;
    -- hash it to a fixed-size, NUL-free digest (bodies can be huge and may
    -- contain NUL, which would break the delimiter)
    if body then
        n = n + 1
        parts[n] = "b:" .. md5(body)
    end
    return plugin_ctx_id(ctx, concat(parts, "\0"))
end


-- decide the cache TTL for an auth response, honoring upstream cache-control.
-- returns nil when the response must not be cached.
local function resolve_cache_ttl(conf, res)
    -- never cache transient server errors from the auth service
    if res.status >= 500 then
        return nil
    end

    local ttl = conf.cache.ttl
    local cc = res.headers["Cache-Control"]
    if type(cc) == "table" then
        cc = concat(cc, ",")
    end
    if cc then
        cc = lower(cc)
        -- a shared cache must not store these
        if find(cc, "no-store", 1, true) or find(cc, "no-cache", 1, true)
           or find(cc, "private", 1, true) then
            return nil
        end
        local max_age = match(cc, "max%-age%s*=%s*(%d+)")
        if max_age then
            max_age = tonumber(max_age)
            if not max_age or max_age <= 0 then
                return nil
            end
            if max_age < ttl then
                ttl = max_age
            end
        end
    end
    return ttl
end


-- normalize an auth response into a compact, cacheable decision
local function build_result(conf, res)
    local result = {status = res.status}
    if res.status >= 300 then
        local client_headers = {}
        for _, header in ipairs(conf.client_headers) do
            client_headers[header] = res.headers[header]
        end
        result.client_headers = client_headers
        result.body = res.body
    else
        local upstream_headers = {}
        for _, header in ipairs(conf.upstream_headers) do
            upstream_headers[header] = res.headers[header]
        end
        result.upstream_headers = upstream_headers
    end
    return result
end


-- replay a decision onto the current request/response
local function apply_result(conf, ctx, result)
    if result.status >= 300 then
        core.response.set_header(result.client_headers)
        return result.status, result.body
    end

    -- set headers from the auth response, clearing any client-supplied values
    -- for configured headers not present in the auth response
    for _, header in ipairs(conf.upstream_headers) do
        core.request.set_header(ctx, header, result.upstream_headers[header])
    end
end


function _M.access(conf, ctx)
    local auth_headers = {
        ["X-Forwarded-Proto"] = core.request.get_scheme(ctx),
        ["X-Forwarded-Method"] = core.request.get_method(),
        ["X-Forwarded-Host"] = core.request.get_host(ctx),
        ["X-Forwarded-Uri"] = ctx.var.request_uri,
        ["X-Forwarded-For"] = core.request.get_remote_client_ip(ctx),
    }

    if conf.request_method == "POST" then
        -- body is buffered and re-framed below, so only keep content-encoding.
        -- forwarding client transfer-encoding/content-length/expect would not
        -- match the buffered body.
        auth_headers["Content-Encoding"] = core.request.header(ctx, "content-encoding")
    end

    if conf.extra_headers then
        for header, value in pairs(conf.extra_headers) do
            if type(value) == "number" then
                value = tostring(value)
            end
            local resolve_value, err = core.utils.resolve_var(value, ctx.var)
            if not err then
                auth_headers[header] = resolve_value
            end
            if err then
                core.log.error("failed to resolve variable in extra header '",
                                header, "': ",value,": ",err)
            end
        end
    end

    -- append headers that need to be get from the client request header
    if #conf.request_headers > 0 then
        for _, header in ipairs(conf.request_headers) do
            if not auth_headers[header] then
                auth_headers[header] = core.request.header(ctx, header)
            end
        end
    end

    local params = {
        headers = auth_headers,
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        method = conf.request_method
    }

    if params.method == "POST" then
        local body, err = core.request.get_body(conf.max_req_body_size)
        if err then
            core.log.error("failed to read request body: ", err)
            return 413
        end
        params.body = body
    end

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local cache_key
    if conf.cache then
        cache_key = build_cache_key(conf, ctx, params.body)
        local cached = auth_cache:get(cache_key)
        if cached then
            return apply_result(conf, ctx, cached)
        end
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(conf.uri, params)
    if not res and conf.allow_degradation then
        return
    elseif not res then
        core.log.warn("failed to process forward auth, err: ", err)
        return conf.status_on_error
    end

    local result = build_result(conf, res)

    if cache_key then
        local ttl = resolve_cache_ttl(conf, res)
        if ttl then
            auth_cache:set(cache_key, result, ttl)
        end
    end

    return apply_result(conf, ctx, result)
end


return _M
