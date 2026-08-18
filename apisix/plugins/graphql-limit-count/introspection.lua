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
--
-- Upstream GraphQL schema introspection.
--
-- Cost decorations are addressed by GraphQL type name, while a query AST only
-- carries field names, so the schema is required to tell `Person.name` from
-- `Vehicle.name`. The schema is fetched lazily on the first request that needs it
-- and then kept for the lifetime of the worker; there is no knob for the TTL, so a
-- schema change on a live upstream needs a reload.
--
local core        = require("apisix.core")
local http        = require("resty.http")
local resty_lock  = require("resty.lock")
local upstream    = require("apisix.upstream")
local service_fetch = require("apisix.http.service").get

local ipairs   = ipairs
local pairs    = pairs
local type     = type
local str_find = string.find
local tab_sort = table.sort
local tostring = tostring
local ngx_now  = ngx.now

local LOCK_SHDICT_NAME = "lrucache-lock"

-- milliseconds; see the comment in fetch_schema
local INTROSPECTION_CONNECT_TIMEOUT = 2000
local INTROSPECTION_SEND_TIMEOUT    = 2000
local INTROSPECTION_READ_TIMEOUT    = 5000
-- seconds a failed introspection is remembered, so an upstream that answers
-- nothing does not get one request per client request
local INTROSPECTION_FAILURE_TTL     = 10

-- Trimmed to what the cost engine consumes: the root type names (`field_path`'s
-- first segment is matched against them), each type's fields and their result
-- types, and the argument default values used by `resolve_variables`.
local INTROSPECTION_QUERY = [[
fragment TypeAttr on __Type {
    kind
    name
}

fragment WrappedTypeRef on __Type {
    ...TypeAttr
    ofType { ...TypeAttr
      ofType { ...TypeAttr
        ofType { ...TypeAttr
          ofType { ...TypeAttr } } } }
}

query {
    __schema {
        queryType { name }
        mutationType { name }
        types {
            ...TypeAttr
            fields {
                name
                args { name defaultValue type { ...WrappedTypeRef } }
                type { ...WrappedTypeRef }
            }
        }
    }
}
]]

-- Headers that describe the downstream request body or connection and must not be
-- copied onto the introspection request when pass_all_downstream_headers is on.
local SKIPPED_DOWNSTREAM_HEADERS = {
    ["host"]              = true,
    ["content-length"]    = true,
    ["content-type"]      = true,
    ["transfer-encoding"] = true,
    ["connection"]        = true,
    ["expect"]            = true,
}

-- Per-worker, keyed by the owning service (or by the explicit endpoint when one
-- is configured). Never invalidated: an upstream schema change only takes effect
-- after a reload. Keying on the service rather than on the derived endpoint is
-- what bounds the table: the endpoint embeds the
-- request path, so a route matching many paths would otherwise add a permanent
-- entry -- and trigger an upstream introspection -- for every distinct path.
local schema_cache = {}
-- cache_key -> {err = <string>, expire_at = <number>}
local failure_cache = {}

local _M = {}


local function unwrap_type_name(type_ref)
    -- NON_NULL / LIST wrappers have no name of their own; descend to the named type.
    while type_ref do
        if type_ref.name then
            return type_ref.name
        end
        type_ref = type_ref.ofType
    end

    return nil
end


local function build_index(schema_data)
    local introspected = schema_data and schema_data.__schema
    if not introspected or type(introspected.types) ~= "table" then
        return nil, "introspection response has no __schema.types"
    end

    local types = {}
    for _, type_def in ipairs(introspected.types) do
        if type_def.name and type_def.fields then
            local fields = {}
            for _, field in ipairs(type_def.fields) do
                if field.name then
                    local args
                    if field.args then
                        for _, arg in ipairs(field.args) do
                            if arg.name and arg.defaultValue ~= nil then
                                args = args or {}
                                args[arg.name] = {default_value = arg.defaultValue}
                            end
                        end
                    end

                    fields[field.name] = {
                        type = unwrap_type_name(field.type),
                        args = args,
                    }
                end
            end
            types[type_def.name] = {fields = fields}
        end
    end

    return {
        query_type    = introspected.queryType and introspected.queryType.name or "Query",
        mutation_type = introspected.mutationType and introspected.mutationType.name
                        or "Mutation",
        types         = types,
    }
end


-- Picks the node the introspection request is sent to. APISIX runs the access
-- phase before the balancer, so there is no resolved peer to reuse:
-- the nodes are sorted and the first one is taken so repeated introspections of
-- the same upstream are stable. Deployments where that is not good enough (service
-- discovery, a separate introspection path) set `introspection_endpoint`.
local function first_node(nodes, scheme)
    local candidates = {}
    local default_port = (scheme == "https" or scheme == "grpcs") and 443 or 80

    if core.table.isarray(nodes) then
        for _, node in ipairs(nodes) do
            if node.host then
                core.table.insert(candidates, node.host .. ":" .. (node.port or default_port))
            end
        end
    else
        for addr in pairs(nodes) do
            core.table.insert(candidates, addr)
        end
    end

    if #candidates == 0 then
        return nil
    end

    tab_sort(candidates)
    return candidates[1]
end


-- Returns the endpoint to introspect and the Host header to send with it, or
-- nil plus an error message.
local function resolve_endpoint(conf, ctx)
    if conf.introspection_endpoint then
        return core.utils.escape_uri_control_chars(conf.introspection_endpoint)
    end

    local route = ctx.matched_route and ctx.matched_route.value
    if not route then
        return nil, "no matched route to derive the introspection endpoint from"
    end

    -- The schema is cached per service, so prefer the service's own upstream:
    -- merge_service_route lets a route override it, and two routes on one service
    -- with different overrides would otherwise share whichever schema was fetched
    -- first. Falls back to the route for a route-only upstream.
    local up_conf
    local service = ctx.service_id and service_fetch(ctx.service_id)
    if service and service.value then
        up_conf = service.value.upstream
        if not up_conf and service.value.upstream_id then
            up_conf = upstream.get_by_id(service.value.upstream_id)
        end
    end

    if not up_conf then
        up_conf = route.upstream
        if not up_conf and route.upstream_id then
            up_conf = upstream.get_by_id(route.upstream_id)
        end
    end

    if not up_conf or not up_conf.nodes then
        return nil, "the route has no upstream nodes, set introspection_endpoint"
    end

    local scheme = up_conf.scheme or "http"
    local addr = first_node(up_conf.nodes, scheme)
    if not addr then
        return nil, "the route has no upstream nodes, set introspection_endpoint"
    end

    local path = ctx.var.upstream_uri
    if not path or path == "" then
        path = ctx.var.uri
    end
    local query_pos = str_find(path, "?", 1, true)
    if query_pos then
        path = path:sub(1, query_pos - 1)
    end
    -- $uri is already percent-decoded, so a request path carrying %0d%0a would
    -- otherwise reach the request line of the introspection call verbatim. Same
    -- treatment $upstream_uri gets in init.lua.
    path = core.utils.escape_uri_control_chars(path)

    -- Mirror what proxied traffic sends, so a virtual-hosted upstream answers the
    -- introspection the same way it answers the query. `node` means "use the node
    -- address", which is what request_uri does on its own. For `pass` the template
    -- leaves $upstream_host at $http_host (cli/ngx_tpl.lua:810) -- the verbatim
    -- header including any port -- so $host, which is lowercased and port-stripped,
    -- would reach a different vhost than the proxied request does.
    local host
    if up_conf.pass_host == "rewrite" then
        host = up_conf.upstream_host
    elseif up_conf.pass_host ~= "node" then
        host = ctx.var.http_host or ctx.var.host
    end

    if host and not core.utils.validate_header_value(host) then
        return nil, "the upstream host is not a valid header value"
    end

    return scheme .. "://" .. addr .. path, nil, host
end


local function build_headers(conf, ctx, host)
    local headers = {["Content-Type"] = "application/json"}

    -- request_uri would otherwise send the node address as the Host, which breaks
    -- a virtual-hosted GraphQL upstream that proxied traffic reaches fine
    if host then
        headers["Host"] = host
    end

    if conf.pass_all_downstream_headers then
        for name, value in pairs(core.request.headers(ctx)) do
            if not SKIPPED_DOWNSTREAM_HEADERS[name:lower()] then
                headers[name] = value
            end
        end
    else
        local authorization = core.request.header(ctx, "Authorization")
        if authorization then
            headers["Authorization"] = authorization
        end
    end

    return headers
end


local function fetch_schema(conf, ctx, endpoint, host)
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client: " .. err
    end

    -- The single-flight lock is held for the whole fetch, so without an explicit
    -- timeout an unresponsive endpoint would park every other request on the lock
    -- until the OpenResty default (60s) expired. Bounded, not configurable.
    httpc:set_timeouts(INTROSPECTION_CONNECT_TIMEOUT, INTROSPECTION_SEND_TIMEOUT,
                       INTROSPECTION_READ_TIMEOUT)

    local res
    res, err = httpc:request_uri(endpoint, {
        method  = "POST",
        body    = core.json.encode({query = INTROSPECTION_QUERY}),
        headers = build_headers(conf, ctx, host),
        -- The introspection target is the upstream this route already proxies to,
        -- whose certificate the proxy path does not verify either.
        ssl_verify = false,
        keepalive  = false,
    })

    if not res then
        return nil, "failed to request " .. endpoint .. ": " .. err
    end

    if res.status ~= 200 then
        return nil, "unexpected status " .. res.status .. " from " .. endpoint
    end

    local body
    body, err = core.json.decode(res.body, {null_as_nil = true})
    if not body then
        return nil, "failed to decode the introspection response: " .. (err or "not an object")
    end

    if not body.data then
        return nil, "introspection response has no data field"
    end

    return build_index(body.data)
end


local function fetch_and_cache(conf, ctx, cache_key, endpoint, host)
    local lock, err = resty_lock:new(LOCK_SHDICT_NAME)
    if not lock then
        core.log.warn("failed to create the introspection lock: ", err,
                      ", fetching the schema without single-flight protection")
        return fetch_schema(conf, ctx, endpoint, host)
    end

    local elapsed
    elapsed, err = lock:lock("graphql-schema#" .. cache_key)
    if not elapsed then
        core.log.warn("failed to acquire the introspection lock: ", err,
                      ", fetching the schema without single-flight protection")
        return fetch_schema(conf, ctx, endpoint, host)
    end

    -- another request may have populated the cache while this one waited
    local cached = schema_cache[cache_key]
    if cached then
        lock:unlock()
        return cached
    end

    local schema, ferr = fetch_schema(conf, ctx, endpoint, host)
    if schema then
        schema_cache[cache_key] = schema
        failure_cache[cache_key] = nil
    else
        failure_cache[cache_key] = {
            err = ferr,
            expire_at = ngx_now() + INTROSPECTION_FAILURE_TTL,
        }
    end
    lock:unlock()

    return schema, ferr
end


---
-- Returns the schema index for the upstream this request is routed to.
function _M.get(conf, ctx)
    -- The derived endpoint embeds the request path, so it is not a safe cache key
    -- (a route matching many paths would grow the table without bound). The schema
    -- belongs to the upstream, and decorations only exist per service, so the
    -- service is both the correct and the bounded key. An explicit endpoint is its
    -- own key: it does not vary per request.
    local cache_key = conf.introspection_endpoint
                      or (ctx.service_id and tostring(ctx.service_id))
    if not cache_key then
        return nil, "the route is not bound to a service, set introspection_endpoint"
    end

    local cached = schema_cache[cache_key]
    if cached then
        return cached
    end

    local failure = failure_cache[cache_key]
    if failure then
        if ngx_now() < failure.expire_at then
            return nil, failure.err
        end
        failure_cache[cache_key] = nil
    end

    local endpoint, err, host = resolve_endpoint(conf, ctx)
    if not endpoint then
        return nil, err
    end

    return fetch_and_cache(conf, ctx, cache_key, endpoint, host)
end


-- Called when the plugin is unloaded or reloaded, which is the only invalidation
-- point the cache has: a schema change on a live upstream still needs a reload.
function _M.flush()
    schema_cache = {}
    failure_cache = {}
end


return _M
