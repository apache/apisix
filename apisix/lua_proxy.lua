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

local function handle_error(err)
    if core.string.find(err, "timeout") then
        return 504
    end
    return 500
end

local function build_request_opts(conf, ctx)
    -- Get upstream server
    local server, err = ctx.picked_server
    if err then
        return nil, "no picked server: " .. err
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
        ssl_verify = conf.ssl_verify,
        keepalive = conf.keepalive,
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


local function read_response(ctx, res)
    local body_reader, err = res.body_reader
    if err then
        core.log.warn("failed to get response body reader: ", err)
        return 500
    end

    local content_type = res.headers["Content-Type"]
    core.response.set_header("Content-Type", content_type)

    if content_type and core.string.find(content_type, "text/event-stream") then
        while true do
            local chunk, err = body_reader() -- will read chunk by chunk
            if err then
                core.log.warn("failed to read response chunk: ", err)
                if core.string.find(err, "timeout") then
                    return 504
                end
                return 500
            end
            if not chunk then
                return
            end

            ngx_print(chunk)
            ngx_flush(true)

            local events, err = ngx_re.split(chunk, "\n")
            if err then
                core.log.warn("failed to split response chunk [", chunk, "] to events: ", err)
                goto CONTINUE
            end

            for _, event in ipairs(events) do
                if not core.string.find(event, "data:") or core.string.find(event, "[DONE]") then
                    goto CONTINUE
                end

                local parts, err = ngx_re.split(event, ":", nil, nil, 2)
                if err then
                    core.log.warn("failed to split data event [", event,  "] to parts: ", err)
                    goto CONTINUE
                end

                if #parts ~= 2 then
                    core.log.warn("malformed data event: ", event)
                    goto CONTINUE
                end

                local data, err = core.json.decode(parts[2])
                if err then
                    core.log.warn("failed to decode data event [", parts[2], "] to json: ", err)
                    goto CONTINUE
                end

            end

            ::CONTINUE::
        end
    end

    local raw_res_body, err = res:read_body()
    if err then
        core.log.warn("failed to read response body: ", err)
        if core.string.find(err, "timeout") then
            return 504
        end
        return 500
    end

    return res.status, raw_res_body
end


_M.request = function (conf, ctx)
    -- Build request options
    local opts, err = build_request_opts(conf, ctx)
    if err then
        core.log.error("failed to build request options: ", err)
        return 500
    end

    -- Create HTTP client
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client to send request to LLM server: " .. err
    end
    httpc:set_timeout(conf.timeout)

    -- Send request
    local ok, err = httpc:connect({
        scheme = opts.scheme,
        host = opts.host,
        port = opts.port,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = opts.host,
        pool_size = conf.keepalive and conf.keepalive_pool,
    })

    if not ok then
        return nil, "failed to connect to upstream: " .. err
    end

    local params = {
        method = opts.method,
        headers = opts.headers,
        keepalive = opts.keepalive,
        ssl_verify = opts.ssl_verify,
        path = opts.path,
        query = opts.query_params,
        body = opts.body
    }

    local res, err = httpc:request(params)
    if not res then
        return nil, err
    end

    local code, body = read_response(ctx, res)

    if opts.keepalive then
        local _, err = httpc:set_keepalive(opts.keepalive_timeout, opts.keepalive_pool)
        if err then
            core.log.warn("failed to keepalive connection: ", err)
        end
    end

    return code, body
end

return _M
