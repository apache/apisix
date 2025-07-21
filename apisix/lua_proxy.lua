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

local HTTP_GATEWAY_TIMEOUT = ngx.HTTP_GATEWAY_TIMEOUT
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR


local function handle_error(err)
    if core.string.find(err, "timeout") then
        return HTTP_GATEWAY_TIMEOUT
    end
    return HTTP_INTERNAL_SERVER_ERROR
end


local function build_request_opts(conf, ctx)
    -- Get upstream server
    local server = ctx.picked_server
    if not server then
        return nil, "no picked server"
    end

    local headers = core.request.headers(ctx)
    -- When content-length is cleared, the HTTP server will automatically calculate and
    -- set the correct content length when sending the response. This ensures that the
    -- content length of the response matches the actual data sent, thereby avoiding mismatches.
    headers["content-length"] = nil

    -- Build request options
    local opts = {
        scheme = server.scheme or ctx.upstream_scheme or "http",
        host = server.domain or server.host,
        port = server.port,
        path = ctx.var.uri,
        query = ctx.var.args,
        method = core.request.get_method(),
        headers = headers,
        ssl_verify = conf.ssl_verify,
        keepalive = conf.keepalive,
        keepalive_timeout = conf.timeout,
        keepalive_pool = conf.keepalive_pool
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


local function read_response(ctx, res)
    local body_reader = res.body_reader
    if not body_reader then
        core.log.error("failed to get response body reader")
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local content_type = res.headers["Content-Type"]
    core.response.set_header("Content-Type", content_type)

    -- TODO: support event stream
    if content_type and core.string.find(content_type, "text/event-stream") then
        core.log.error("event stream is not supported")
       return HTTP_INTERNAL_SERVER_ERROR
    end

    local raw_res_body, err = res:read_body()
    if err then
        core.log.error("failed to read response body: ", err)
        return handle_error(err)
    end

    return res.status, raw_res_body
end


function _M.request(conf, ctx)
    -- Build request options
    local opts, err = build_request_opts(conf, ctx)
    if err then
        core.log.error("failed to build request options: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Create HTTP client
    local httpc, err = http.new()
    if err then
        return nil, "failed to create http client: " .. err
    end
    httpc:set_timeout(opts.timeout)

    -- Connect to upstream
    local ok, err = httpc:connect({
        scheme = opts.scheme,
        host = opts.host,
        port = opts.port,
        ssl_verify = opts.ssl_verify,
        ssl_server_name = opts.host,
        pool_size = opts.keepalive,
    })

    if not ok then
        return nil, "failed to connect to upstream: " .. err
    end

    -- Prepare request parameters
    local params = {
        method = opts.method,
        headers = opts.headers,
        keepalive = opts.keepalive,
        ssl_verify = opts.ssl_verify,
        path = opts.path,
        query = opts.query,
        body = opts.body
    }

    -- Send request
    local res, err = httpc:request(params)
    if err then
        return nil, err
    end

    -- Handle response
    local code, body = read_response(ctx, res)

    -- Set keepalive for connection reuse
    if opts.keepalive then
        local _, err = httpc:set_keepalive(opts.keepalive_timeout, opts.keepalive_pool)
        if err then
            core.log.error("failed to keepalive connection: ", err)
        end
    end

    return code, body
end

return _M
