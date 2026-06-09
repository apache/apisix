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
local type = type
local str_lower = string.lower

local _M = {}


--- Map network errors to HTTP status codes.
function _M.handle_error(err)
    if core.string.find(err, "timeout") then
        return 504
    end
    return 500
end


--- Build forwarded headers from client request + extra headers.
-- Copies client headers, merges ext_opts_headers (lowercased),
-- forces Content-Type to application/json, removes host/content-length.
function _M.construct_forward_headers(ext_opts_headers, ctx)
    local blacklist = {
        "host",
        "content-length",
        "accept-encoding",
    }

    local headers = {}
    for k, v in pairs(core.request.headers(ctx) or {}) do
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
    local httpc, err = http.new()
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
        req_json, err = core.json.encode(params.body)
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
