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
local http_client = require("apisix.utils.http")
local url = require("socket.url")
local ngx_now = ngx.now
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local type = type
local str_lower = string.lower
local tonumber = tonumber
local tostring = tostring

local attr_schema = {
    type = "object",
    properties = {
        http_client = http_client.client_schema,
    },
}

local _M = {}

local client_name


--- Which client this transport should use.
-- `plugin_attr.ai-proxy.http_client` names it; the shared module owns the
-- names, validation and loading. Read on first request, because local_conf is
-- not readable while this module is still loading.
local function resolve_client_name()
    if client_name then
        return client_name
    end

    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr", "ai-proxy") or {}

    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("invalid plugin_attr.ai-proxy: ", err)
        return nil, "invalid plugin_attr.ai-proxy: " .. err
    end

    client_name = attr.http_client or http_client.DEFAULT_CLIENT

    return client_name
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


-- Redirect statuses that preserve the method and the body, so the request can
-- be replayed unchanged. 301/302/303 are deliberately absent: they permit the
-- method to be rewritten to GET, which would silently drop the prompt.
local REDIRECT_STATUSES = {
    [307] = true,
    [308] = true,
}


--- Follow one same-origin 307/308 redirect, reusing the open connection.
-- Providers that route through a redirect (The Grid's Consumption API answers
-- with a documented 307 to its routing layer) need it followed inside the
-- gateway: returning the 3xx downstream would leave the Plugin blind to the
-- real response, so token usage, retries and instance fallback would all see a
-- request that never produced any tokens.
--
-- Only same-origin redirects are followed. A cross-origin hop would replay the
-- provider credentials in `Authorization` against a host chosen by the
-- response, so it is refused rather than followed.
-- @param httpc table Connected HTTP client
-- @param params table Request parameters that produced `res`
-- @param res table The redirect response
-- @return table|nil New response object
-- @return string|nil Error message
local function follow_redirect(httpc, params, res)
    local location = res.headers["Location"] or res.headers["location"]
    if not location then
        return nil, "redirect response carried no Location header"
    end

    local parsed = url.parse(location)
    if not parsed or not parsed.path then
        return nil, "could not parse Location header"
    end

    -- A Location without a host is relative, and therefore same-origin already.
    if parsed.host then
        local scheme = parsed.scheme or params.scheme
        local port = tonumber(parsed.port)
                     or (scheme == "https" and 443 or 80)
        if parsed.host ~= params.host
           or scheme ~= params.scheme
           or port ~= tonumber(params.port) then
            return nil, "refusing to follow cross-origin redirect to " .. location
        end
    end

    -- The connection is reused for the replay, so the redirect's own body has
    -- to be drained off the wire first.
    local _, read_err = res:read_body()
    if read_err then
        return nil, "failed to drain redirect body: " .. read_err
    end

    local next_params = {}
    for k, v in pairs(params) do
        next_params[k] = v
    end
    next_params.path = parsed.path
    -- A redirect target that carries its own query string replaces the original
    -- one, which belonged to the hop that has already been answered. Without
    -- one, the original is kept, so providers that authenticate through
    -- `auth.query` still reach the target authenticated.
    if parsed.query then
        next_params.query = parsed.query
    end

    local next_res, err = httpc:request(next_params)
    if not next_res then
        return nil, "redirect request: " .. (err or "unknown")
    end

    return next_res
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
    local name, name_err = resolve_client_name()
    if not name then
        return nil, "failed to create http client: " .. name_err
    end

    local httpc, err = http_client.new(name)
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

    if params.follow_redirects and REDIRECT_STATUSES[res.status] then
        local redirected, redirect_err = follow_redirect(httpc, params, res)
        if not redirected then
            httpc:close()
            return nil, redirect_err, {
                upstream_addr = upstream_addr,
                upstream_host = upstream_host,
                upstream_scheme = upstream_scheme,
                upstream_uri = params.path,
                connect_time = connect_time,
                t0 = t0,
            }
        end
        res = redirected
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
