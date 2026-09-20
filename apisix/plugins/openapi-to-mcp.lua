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
local core        = require("apisix.core")
local streamable_http = require("apisix.plugins.openapi-to-mcp.transport.streamable_http")
local mcp_sse         = require("apisix.plugins.openapi-to-mcp.transport.sse")
local ngx         = ngx
local pairs       = pairs
local ipairs      = ipairs
local type        = type
local str_lower   = string.lower
local str_match   = string.match
local str_sub     = string.sub

local schema = {
    type = "object",
    properties = {
        transport = {
            description = "The transport mechanisms for client-server communication",
            type = "string",
            default = "sse",
            enum = {"sse", "streamable_http"},
        },
        openapi_url = {
            description = "URL of the OpenAPI specification document",
            type = "string",
            minLength = 1,
        },
        base_url = {
            description = "Base URL of the external service",
            type = "string",
            minLength = 1,
        },
        headers = {
            description = "Headers to include in requests to the external service",
            type = "object",
            minProperties = 0,
            patternProperties = {
                -- no colon and no whitespace in the name, no CR or LF in the
                -- value: either would let a resolved variable add a header, or
                -- a request, of its own. These anchor with $ rather than \z,
                -- which is PCRE-only: this schema is served over the Admin API
                -- and is validated by clients whose regex flavour has no \z,
                -- where it would degrade to a literal "z". The gap $ leaves in
                -- PCRE -- it also matches before a trailing newline -- is
                -- closed at request time, where a header is dropped unless
                -- fetch.header_is_sane() accepts its name and its resolved
                -- value.
                ["^[^:\\s]+$"] = {
                    oneOf = {
                        { type = "string", pattern = "^[^\\r\\n]*$" }
                    }
                }
            },
            -- patternProperties only constrains the names it matches; without
            -- this a name the pattern rejects would simply go unchecked
            additionalProperties = false,
        },
        max_response_body_size = {
            description = "Maximum size, in bytes, of an upstream response " ..
            "body read into a tool result. A larger response fails the call.",
            type = "integer",
            minimum = 1024,
            default = 1048576,
        },
        max_document_size = {
            description = "Maximum size in bytes of the OpenAPI document, and " ..
            "of any document an http(s) $ref pulls in.",
            type = "integer",
            minimum = 1024,
            default = 4194304,
        },
        allowed_ref_hosts = {
            description = "Hosts an http(s) $ref inside the OpenAPI document " ..
            "may point at, besides the origin of openapi_url itself. Each " ..
            "entry is a hostname or a `*.example.com` wildcard, optionally " ..
            "followed by `:port`; without a port it matches any port.",
            type = "array",
            minItems = 1,
            uniqueItems = true,
            items = { type = "string", minLength = 1 },
        },
        allowed_origins = {
            description = "Origin header values accepted on MCP requests, as " ..
            "scheme://host[:port]. A request with no Origin header is always " ..
            "accepted. When unset, an Origin is accepted only if its host is " ..
            "a literal host the route declares in host/hosts -- a wildcard " ..
            "entry does not count -- or if both it and the request are on a " ..
            "loopback address. [\"*\"] accepts any origin.",
            type = "array",
            minItems = 1,
            uniqueItems = true,
            items = { type = "string", minLength = 1 },
        },
        flatten_parameters = {
            description = "Whether to flatten query and path parameters " ..
            "in the tool inputSchema. When false (default), " ..
            "parameters are nested under queryParameters or pathParameters. " ..
            "When true, parameters are placed directly in properties.",
            type = "boolean",
            default = false,
        },
    },
    required = { "openapi_url", "base_url" },
}

local plugin_name = "openapi-to-mcp"

local _M = {
    version  = 0.1,
    priority = 540,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Resolve base_url and headers against request variables.
local function resolve_conf(conf, ctx)
    local base_url, err = core.utils.resolve_var(conf.base_url, ctx.var)
    if err then
        core.log.error("failed to resolve variable for base_url: ",
                       conf.base_url, ", error: ", err)
        base_url = conf.base_url
    end

    local headers = {}
    for key, value in pairs(conf.headers or {}) do
        local resolved_value, herr = core.utils.resolve_var(value, ctx.var)
        if herr then
            core.log.error("failed to resolve variable for header, key: ", key,
                           ", error: ", herr)
            resolved_value = value
        end
        headers[key] = resolved_value
    end

    return base_url, headers
end


function _M.access(conf, ctx)
    if conf.transport == "streamable_http" then
        local base_url, headers = resolve_conf(conf, ctx)

        -- Defer the answer to before_proxy. Exiting here would skip every
        -- plugin with a lower priority that still has to run in access, such
        -- as an authorization check on the tool being called.
        ctx.mcp_inprocess_opts = {
            conf = conf,
            base_url = base_url,
            headers = headers,
            transport = "streamable_http",
        }
        -- The answer is produced in before_proxy, so the request never reaches
        -- an upstream; handle_upstream() runs before_proxy and returns.
        ctx.bypass_nginx_upstream = true
        return
    end

    if conf.transport ~= "sse" then
        core.log.error("Invalid MCP transport: ", conf.transport)
        return 500, { message = "Invalid MCP transport"}
    end

    local base_url, headers = resolve_conf(conf, ctx)

    -- The client is told to POST its messages to the path the route matched.
    local message_path = ctx.curr_req_matched and ctx.curr_req_matched._path

    ngx.ctx.disable_proxy_buffering = true
    ctx.mcp_inprocess_opts = {
        conf = conf,
        base_url = base_url,
        headers = headers,
        transport = "sse",
        message_path = message_path,
    }
    ctx.bypass_nginx_upstream = true
end


-- MCP asks an HTTP transport to check Origin, because a page in a browser can
-- otherwise reach a server that is only listening on localhost, or one behind
-- the user's firewall, and read the answer back.
--
-- A request with no Origin is left alone: it did not come from a browser, and
-- every non-browser MCP client sends none. One that does carry an Origin is
-- accepted only against something the operator configured, never against
-- another header of the same request: under DNS rebinding the attacker owns
-- the name, so Origin and Host are both theirs and agree with each other.
--
-- Three things count as configured, in this order:
--   * allowed_origins on the Plugin, ["*"] there accepting any origin;
--   * a literal host the Route declares, which the operator wrote and the
--     attacker's name does not satisfy -- a request carrying another Host does
--     not match such a Route at all. A wildcard entry does not count, see
--     below;
--   * a loopback address at both ends, which is the case MCP is written
--     around: a page can only have http://localhost as its origin if it is
--     served from the machine itself, and no rebinding produces that.
-- A Route with none of them refuses every request that carries an Origin.
local DEFAULT_PORT = { http = "80", https = "443" }

local LOOPBACK_HOST = {
    ["localhost"] = true,
    ["127.0.0.1"] = true,
    ["::1"] = true,
}


-- "host", "host:port", "[::1]" or "[::1]:port" into a host and a port, the
-- scheme's default port standing in for an absent one.
local function split_authority(authority, scheme)
    local host, port = str_match(authority, "^%[(.+)%]:(%d+)$")
    if not host then
        host = str_match(authority, "^%[(.+)%]$")
    end
    if not host then
        host, port = str_match(authority, "^([^:]+):(%d+)$")
    end
    if not host then
        host = authority
    end
    return str_lower(host or ""), port or DEFAULT_PORT[scheme] or ""
end


-- An Origin as its host and its full "scheme://host:port", or nil for one that
-- names no origin at all -- "null", which a sandboxed frame and a file:// page
-- both send.
local function parse_origin(value)
    if type(value) ~= "string" then
        return nil
    end
    local scheme, authority = str_match(value, "^(%a[%w+.-]*)://(.+)$")
    if not scheme then
        return nil
    end
    scheme = str_lower(scheme)
    local host, port = split_authority(authority, scheme)
    if host == "" then
        return nil
    end
    return scheme .. "://" .. host .. ":" .. port, host
end


-- The literal hosts the Route declares, which is configuration rather than
-- anything the request carries.
--
-- A "*.example.com" entry does not count. It is a routing predicate -- it says
-- which requests reach this Route, not which origins are trusted -- and
-- whoever controls any one name under it can serve a page there and rebind it
-- to the gateway, which is the attack this check exists for. A Route matched
-- on a wildcard has to name the origins it accepts in allowed_origins.
local function literal_route_hosts(ctx)
    local route = ctx.matched_route and ctx.matched_route.value
    if not route then
        return nil
    end
    local declared = route.hosts or (route.host and { route.host })
    if not declared then
        return nil
    end

    local literal
    for _, host in ipairs(declared) do
        if str_sub(host, 1, 1) ~= "*" then
            literal = literal or {}
            literal[#literal + 1] = str_lower(host)
        end
    end
    return literal
end


local function origin_rejected(conf, ctx)
    local origin = core.request.header(ctx, "origin")
    if origin == nil then
        return false
    end
    if type(origin) ~= "string" then
        -- more than one Origin header: nothing sends that, and there is no
        -- single origin to compare
        core.log.warn("rejected an MCP request carrying more than one Origin")
        return true
    end

    local normalised, origin_host = parse_origin(origin)
    local allowed = conf.allowed_origins

    if allowed then
        for _, entry in ipairs(allowed) do
            if entry == "*" or entry == origin
               or (normalised ~= nil and parse_origin(entry) == normalised)
            then
                return false
            end
        end
        core.log.warn("rejected an MCP request with a disallowed Origin")
        return true
    end

    if origin_host ~= nil then
        local hosts = literal_route_hosts(ctx)
        if hosts then
            for _, host in ipairs(hosts) do
                if host == origin_host then
                    return false
                end
            end
            core.log.warn("rejected an MCP request whose Origin is not a host ",
                          "of this route")
            return true
        end

        -- No configuration to check against. Loopback at both ends is the one
        -- case that is still safe: an attacker's page cannot be served from
        -- the machine the gateway runs on.
        local host_header = core.request.header(ctx, "host")
        if LOOPBACK_HOST[origin_host] and type(host_header) == "string" then
            local request_host = split_authority(host_header,
                                                 str_lower(ctx.var.scheme or "http"))
            if LOOPBACK_HOST[request_host] then
                return false
            end
        end
    end

    core.log.warn("rejected an MCP request carrying an Origin this route has ",
                  "nothing to check it against; list it in allowed_origins")
    return true
end


function _M.before_proxy(conf, ctx)
    local opts = ctx.mcp_inprocess_opts
    if not opts then
        return
    end

    -- Every body the transports produce is JSON, and core.response.exit() sets
    -- no content type of its own, so without this they would all go out as
    -- text/plain. Set once here so no rejection path can miss it, the origin
    -- one below included; the two that stream override it with
    -- text/event-stream on their way out.
    core.response.set_header("Content-Type", "application/json")

    if origin_rejected(conf, ctx) then
        return core.response.exit(403, { message = "Origin not allowed" })
    end

    if opts.transport == "sse" then
        return mcp_sse.handle(ctx, opts)
    end
    return streamable_http.handle(ctx, opts)
end


return _M
