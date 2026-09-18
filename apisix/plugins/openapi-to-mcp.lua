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
            "accepted. When unset, a request that carries one is accepted only " ..
            "from the origin it was addressed to. [\"*\"] accepts any origin.",
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
-- every non-browser MCP client sends none. A request that does carry one is
-- accepted only from the origin the request was addressed to, unless the Route
-- names the origins it expects in allowed_origins -- ["*"] there accepts any.
--
-- What this stops is a page on another origin calling the Route. It is not by
-- itself a defence against DNS rebinding, where the attacker owns the name and
-- so both Origin and Host are theirs; a Route that declares `hosts` is not
-- reachable that way at all, because a request carrying another Host does not
-- match it.
local DEFAULT_PORT = { http = "80", https = "443" }


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


-- An Origin as "scheme://host:port", or nil for one that names no origin at
-- all -- "null", which a sandboxed frame and a file:// page both send.
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
    return scheme .. "://" .. host .. ":" .. port
end


-- The origin this request was addressed to, in the same shape.
local function request_origin(ctx)
    local host_header = core.request.header(ctx, "host")
    if type(host_header) ~= "string" or host_header == "" then
        return nil
    end
    local scheme = str_lower(ctx.var.scheme or "http")
    local host, port = split_authority(host_header, scheme)
    if host == "" then
        return nil
    end
    return scheme .. "://" .. host .. ":" .. port
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

    local parsed = parse_origin(origin)
    local allowed = conf.allowed_origins

    if allowed then
        for _, entry in ipairs(allowed) do
            if entry == "*" or entry == origin
               or (parsed ~= nil and parse_origin(entry) == parsed)
            then
                return false
            end
        end
        core.log.warn("rejected an MCP request with a disallowed Origin")
        return true
    end

    if parsed ~= nil and parsed == request_origin(ctx) then
        return false
    end
    core.log.warn("rejected an MCP request from another origin; list it in ",
                  "allowed_origins to accept it")
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
