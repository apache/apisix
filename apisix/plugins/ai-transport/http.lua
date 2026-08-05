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
local http = require("resty.http")
local ngx_now = ngx.now
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local require = require
local type = type
local str_lower = string.lower
local tostring = tostring

local FFI_CLIENT_MODULE = "resty.ngx_http_ffi_client"

local _M = {}

local ffi_client
local ffi_client_resolved


--- Pick the outbound HTTP client.
-- `ngx_http_ffi_client` is a C client with the same object API as
-- lua-resty-http and roughly a third of its outbound CPU cost, but it only
-- exists when the gateway runtime was built with the module. It is preferred
-- whenever present, and lua-resty-http stays the fallback.
-- `plugin_attr.ai-proxy.http_client` forces the choice: "auto" (default),
-- "ffi" or "lua-resty-http".
-- Resolved once per worker, on first request, because local_conf is not
-- readable while the module is still loading.
local function resolve_ffi_client()
    if ffi_client_resolved then
        return ffi_client
    end
    ffi_client_resolved = true

    local local_conf = core.config.local_conf()
    local want = core.table.try_read_attr(local_conf, "plugin_attr",
                                          "ai-proxy", "http_client") or "auto"

    if want == "lua-resty-http" then
        core.log.info("ai transport pinned to lua-resty-http")
        return nil
    end

    local ok, mod = pcall(require, FFI_CLIENT_MODULE)
    if not ok or type(mod) ~= "table" then
        if want == "ffi" then
            core.log.error("plugin_attr.ai-proxy.http_client is \"ffi\" but ",
                           FFI_CLIENT_MODULE, " is missing: ", mod)
        else
            core.log.info(FFI_CLIENT_MODULE, " is not available, ",
                          "using lua-resty-http")
        end
        return nil
    end

    ffi_client = mod

    return ffi_client
end


--- Create an HTTP client, preferring the FFI one.
-- The Lua half of `ngx_http_ffi_client` loads even when the C module is not
-- compiled into the runtime; new() is what reports that, so a failure here
-- falls back for the rest of the worker's life.
local function new_client()
    local client = resolve_ffi_client()
    if client then
        local httpc, err = client.new()
        if httpc then
            return httpc
        end

        core.log.warn("failed to create ", FFI_CLIENT_MODULE, ", ",
                      "falling back to lua-resty-http: ", err or "unknown")
        ffi_client = nil
    end

    return http.new()
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
-- forces Content-Type to application/json, drops the headers that belong to
-- the downstream connection rather than the upstream one.
-- `client_headers` is the downstream request's headers to forward (proxy path),
-- or nil for a self-contained internal request (e.g. ai-request-rewrite calling
-- an LLM to rewrite the body), which must not leak the client's Authorization,
-- Cookie or other headers to a third-party endpoint. The caller passes them in
-- explicitly, so the transport carries no `ctx` / downstream-request coupling.
function _M.construct_forward_headers(ext_opts_headers, client_headers)
    -- connection and transfer-encoding are hop-by-hop: they describe the
    -- downstream connection, and forwarding them desyncs the upstream one.
    -- The client frames the body itself with content-length.
    local blacklist = {
        "host",
        "content-length",
        "accept-encoding",
        "connection",
        "transfer-encoding",
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
