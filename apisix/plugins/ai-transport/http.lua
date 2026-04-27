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
-- @return table|nil Response object (with body_reader, headers, status)
-- @return string|nil Error message
function _M.request(params, timeout)
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client: " .. (err or "unknown")
    end
    httpc:set_timeout(timeout)

    local ok, err = httpc:connect(params)
    if not ok then
        return nil, "connect: " .. (err or "unknown")
    end

    local req_json
    if type(params.body) == "string" then
        -- Body already serialized (e.g., by SigV4 signing)
        req_json = params.body
    else
        local err
        req_json, err = core.json.encode(params.body)
        if not req_json then
            return nil, "encode body: " .. (err or "unknown")
        end
    end
    params.body = req_json

    local res, err = httpc:request(params)
    if not res then
        return nil, "request: " .. (err or "unknown")
    end

    -- Attach httpc to res so caller can manage keepalive
    res._httpc = httpc

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
