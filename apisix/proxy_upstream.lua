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
local _M = {}
local core = require("apisix.core")
local http = require("resty.http")
local plugin = require("apisix.plugin")
local ngx = ngx

local function build_request_opts(conf, ctx)
    -- Get upstream server
    local server = ctx.picked_server
    if not server then
        return nil, "no picked server"
    end

    -- Build request options
    local opts = {
        scheme = server.scheme or ctx.upstream_scheme or "http",
        host = server.domain or server.host,
        port = server.port,
        path = ctx.var.uri,
        query = ctx.var.args,
        method = core.request.get_method(),
        headers = core.request.headers(ctx),
        ssl_verify = conf.ssl_verify or false,
        keepalive = conf.keepalive or true,
        keepalive_timeout = conf.timeout or 60000,
        keepalive_pool = conf.keepalive_pool or 5
    }

    -- Set upstream URI
    if ctx.var.upstream_uri ~= "" then
        opts.path = ctx.var.upstream_uri
    end

    -- Get request body
    local body, err = core.request.get_body()
    if err then
        core.log.error("failed to get request body: ", err)
    end
    if body then
        opts.body = body
    end

    return opts
end

_M.proxy_upstream = function (conf, ctx)
    -- Build request options
    local opts, err = build_request_opts(conf, ctx)
    if not opts then
        core.log.error("failed to build request options: ", err)
        return 500
    end

    core.log.info("sending request to upstream: ", core.json.delay_encode(opts))

    -- Create HTTP client
    local httpc = http.new()
    if not httpc then
        core.log.error("failed to create http client")
        return 500
    end

    -- Send request
    local res, err = httpc:request_uri(opts.scheme .. "://" .. opts.host .. ":" .. opts.port .. opts.path, {
        method = opts.method,
        headers = opts.headers,
        query = opts.query,
        body = opts.body,
        ssl_verify = opts.ssl_verify,
        keepalive = opts.keepalive,
        keepalive_timeout = opts.keepalive_timeout,
        keepalive_pool = opts.keepalive_pool
    })

    if not res then
        core.log.error("failed to request: ", err)
        return 500
    end

    -- Set response
    if res.status ~= 200 then
        core.log.warn("upstream returned non-200 status: ", res.status)
    end

    -- Set response headers
    for k, v in pairs(res.headers) do
        core.response.set_header(k, v)
    end

    plugin.lua_body_filter(res.body, ctx)
    -- Return response body and status code
    return res.status, res.body
end

return _M
