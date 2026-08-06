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

--- HTTP transport helpers.
-- Provides HTTP client lifecycle management for AI provider requests.

local core = require("apisix.core")
local ngx_now = ngx.now
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local require = require
local type = type
local str_lower = string.lower
local tonumber = tonumber
local tostring = tostring

local FFI_CLIENT = "ngx_http_ffi_client"
local LUA_RESTY_HTTP = "lua-resty-http"

-- the client name in the config is not the module name
local CLIENT_MODULES = {
    [FFI_CLIENT] = "resty.ngx_http_ffi_client",
    [LUA_RESTY_HTTP] = "resty.http",
}

local attr_schema = {
    type = "object",
    properties = {
        http_client = {
            type = "string",
            enum = {FFI_CLIENT, LUA_RESTY_HTTP},
            default = FFI_CLIENT,
        },
    },
}

local _M = {}

local http_client
local http_client_is_ffi


--- Pick the outbound HTTP client.
-- `plugin_attr.ai-proxy.http_client` names it: "ngx_http_ffi_client", the
-- default, or "lua-resty-http". The first is a C client with the same object
-- API as the second and around half its outbound CPU cost, and it exists only
-- when the gateway runtime was built with the module.
-- Resolved on first request, because local_conf is not readable while the
-- module is still loading, and cached only once a client has been loaded.
local function resolve_client()
    if http_client then
        return http_client
    end

    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr", "ai-proxy") or {}

    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("invalid plugin_attr.ai-proxy: ", err)
        return nil, "invalid plugin_attr.ai-proxy: " .. err
    end

    local name = attr.http_client or FFI_CLIENT
    local module_name = CLIENT_MODULES[name]

    local mod
    ok, mod = pcall(require, module_name)
    if not ok or type(mod) ~= "table" then
        core.log.error(module_name, " is not available: ", mod)
        return nil, module_name .. " is not available: " .. tostring(mod)
    end

    http_client = mod
    http_client_is_ffi = name == FFI_CLIENT

    return http_client
end


--- Resolve the upstream name the way every other socket in the gateway does.
-- Cosockets are patched (apisix/patch.lua) to run names through
-- core.resolver, which honours dns_resolver, /etc/hosts and the search
-- domains. The C client dials on its own and only sees nginx's `resolver`,
-- so the name is resolved here and kept for the Host header and the SNI.
local function resolve_upstream_host(params)
    local host = params.host
    if not host
       or core.utils.parse_ipv4(host)
       or core.utils.parse_ipv6(host)
    then
        return true
    end

    local ip, err = core.resolver.parse_domain(host)
    if not ip then
        return nil, "failed to parse domain: " .. (err or "unknown")
    end

    params.ssl_server_name = params.ssl_server_name or host

    local headers = params.headers or {}
    if not headers["Host"] and not headers["host"] then
        local default_port = params.scheme == "https" and 443 or 80
        if params.port and tonumber(params.port) ~= default_port then
            headers["Host"] = host .. ":" .. params.port
        else
            headers["Host"] = host
        end
    end
    params.headers = headers

    params.host = ip

    return true
end


--- Create an HTTP client.
-- The Lua half of `ngx_http_ffi_client` loads even when the C module is not
-- compiled into the runtime; new() is what reports that. Either way the
-- failure is returned, never worked around with the other client.
local function new_client()
    local client, err = resolve_client()
    if not client then
        return nil, err
    end

    return client.new()
end


--- Map network errors to HTTP status codes.
-- Cosocket timers report "timeout"; OS errno (ETIMEDOUT) and the resolver
-- report "... timed out", so both spellings must be matched.
function _M.handle_error(err)
    if core.string.find(err, "timeout") or core.string.find(err, "timed out") then
        return 504
    end
    return 500
end


--- Build forwarded headers from client request + extra headers.
-- Copies `client_headers`, merges ext_opts_headers (lowercased),
-- forces Content-Type to application/json, removes host/content-length.
-- `client_headers` is the downstream request's headers to forward (proxy path),
-- or nil for a self-contained internal request (e.g. ai-request-rewrite calling
-- an LLM to rewrite the body), which must not leak the client's Authorization,
-- Cookie or other headers to a third-party endpoint. The caller passes them in
-- explicitly, so the transport carries no `ctx` / downstream-request coupling.
function _M.construct_forward_headers(ext_opts_headers, client_headers)
    local blacklist = {
        "host",
        "content-length",
        "accept-encoding",
    }

    local headers = {}
    for k, v in pairs(client_headers or {}) do
        headers[str_lower(k)] = v
    end
    for k, v in pairs(ext_opts_headers or {}) do
        headers[str_lower(k)] = v
    end
    headers["content-type"] = "application/json"

    for _, h in ipairs(blacklist) do
        headers[h] = nil
    end

    return headers
end


local function encode_body(body)
    local ok, encoded = pcall(core.json.canonical_encode, body)
    if ok and encoded then
        return encoded
    end

    core.log.error("failed to encode AI request body with rapidjson: ",
                  ok and "unknown" or tostring(encoded),
                  ", fallback to cjson; LLM cache hit rate may decrease")

    return core.json.encode(body)
end


--- Send an HTTP request to an AI service.
-- Handles the full lifecycle: create client, connect, encode body,
-- send request, and return the response object.
-- @param params table HTTP request parameters:
--   {method, scheme, host, port, path, headers, query, body (table),
--    ssl_verify, ssl_server_name}
-- @param timeout number Request timeout in milliseconds
-- @return table|nil Response object (with body_reader, headers, status,
--   _upstream_addr, _upstream_uri, _connect_time, _header_time, _t0)
-- @return string|nil Error message
-- @return table|nil Upstream metadata on failure (for recording failed attempts)
function _M.request(params, timeout)
    local httpc, err = new_client()
    if not httpc then
        return nil, "failed to create http client: " .. (err or "unknown")
    end
    httpc:set_timeout(timeout)

    local upstream_addr = (params.host or "") .. ":" .. (params.port or "")
    local upstream_host = params.host or ""
    local upstream_scheme = params.scheme or "http"
    local t0 = ngx_now()

    if http_client_is_ffi then
        local resolved, rerr = resolve_upstream_host(params)
        if not resolved then
            return nil, "connect: " .. rerr, {
                upstream_addr = upstream_addr,
                upstream_host = upstream_host,
                upstream_scheme = upstream_scheme,
                upstream_uri = params.path,
                t0 = t0,
            }
        end
    end

    local ok, err = httpc:connect(params)
    if not ok then
        return nil, "connect: " .. (err or "unknown"), {
            upstream_addr = upstream_addr,
            upstream_host = upstream_host,
            upstream_scheme = upstream_scheme,
            upstream_uri = params.path,
            t0 = t0,
        }
    end

    local connect_time = (ngx_now() - t0) * 1000

    local req_json
    if type(params.body) == "string" then
        -- Body already serialized (e.g., by SigV4 signing)
        req_json = params.body
    else
        local err
        req_json, err = encode_body(params.body)
        if not req_json then
            httpc:close()
            return nil, "encode body: " .. (err or "unknown"), {
                upstream_addr = upstream_addr,
                upstream_host = upstream_host,
                upstream_scheme = upstream_scheme,
                upstream_uri = params.path,
                connect_time = connect_time,
                t0 = t0,
            }
        end
    end
    params.body = req_json

    local res, err = httpc:request(params)
    if not res then
        httpc:close()
        return nil, "request: " .. (err or "unknown"), {
            upstream_addr = upstream_addr,
            upstream_host = upstream_host,
            upstream_scheme = upstream_scheme,
            upstream_uri = params.path,
            connect_time = connect_time,
            t0 = t0,
        }
    end

    local header_time = (ngx_now() - t0) * 1000

    -- Attach httpc and upstream metadata to res
    res._httpc = httpc
    res._upstream_addr = upstream_addr
    res._upstream_host = upstream_host
    res._upstream_scheme = upstream_scheme
    res._upstream_uri = params.path
    res._connect_time = connect_time
    res._header_time = header_time
    res._t0 = t0

    return res
end


--- Set keepalive on the HTTP connection attached to a response.
-- @param res table Response object returned by request()
-- @param keepalive_timeout number Keepalive timeout in milliseconds
-- @param keepalive_pool number Keepalive pool size
function _M.set_keepalive(res, keepalive_timeout, keepalive_pool)
    if not res or not res._httpc then
        return
    end
    local ok, err = res._httpc:set_keepalive(keepalive_timeout, keepalive_pool)
    if not ok then
        core.log.warn("failed to keepalive connection: ", err)
    end
end


return _M
