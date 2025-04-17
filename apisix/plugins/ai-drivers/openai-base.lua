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

local mt = {
    __index = _M
}

local CONTENT_TYPE_JSON = "application/json"

local core = require("apisix.core")
local http = require("resty.http")
local url  = require("socket.url")
local ngx_re = require("ngx.re")

local ngx_print = ngx.print
local ngx_flush = ngx.flush

local pairs = pairs
local type  = type
local ipairs = ipairs
local setmetatable = setmetatable


function _M.new(opts)

    local self = {
        host = opts.host,
        port = opts.port,
        path = opts.path,
    }
    return setmetatable(self, mt)
end


function _M.validate_request(ctx)
        local ct = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
        if not core.string.has_prefix(ct, CONTENT_TYPE_JSON) then
            return nil, "unsupported content-type: " .. ct .. ", only application/json is supported"
        end

        local request_table, err = core.request.get_json_request_body_table()
        if not request_table then
            return nil, err
        end

        return request_table, nil
end


function _M.request(self, conf, request_table, extra_opts)
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client to send request to LLM server: " .. err
    end
    httpc:set_timeout(conf.timeout)

    local endpoint = extra_opts.endpoint
    local parsed_url
    if endpoint then
        parsed_url = url.parse(endpoint)
    end

    local ok, err = httpc:connect({
        scheme = parsed_url and parsed_url.scheme or "https",
        host = parsed_url and parsed_url.host or self.host,
        port = parsed_url and parsed_url.port or self.port,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = parsed_url and parsed_url.host or self.host,
        pool_size = conf.keepalive and conf.keepalive_pool,
    })

    if not ok then
        return nil, "failed to connect to LLM server: " .. err
    end

    local query_params = extra_opts.query_params

    if type(parsed_url) == "table" and parsed_url.query and #parsed_url.query > 0 then
        local args_tab = core.string.decode_args(parsed_url.query)
        if type(args_tab) == "table" then
            core.table.merge(query_params, args_tab)
        end
    end

    local path = (parsed_url and parsed_url.path or self.path)

    local headers = extra_opts.headers
    headers["Content-Type"] = "application/json"
    local params = {
        method = "POST",
        headers = headers,
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        path = path,
        query = query_params
    }

    if extra_opts.model_options then
        for opt, val in pairs(extra_opts.model_options) do
            request_table[opt] = val
        end
    end

    local req_json, err = core.json.encode(request_table)
    if not req_json then
        return nil, err
    end

    params.body = req_json

    local res, err = httpc:request(params)
    if not res then
        return nil, err
    end

    return res, nil
end


function _M.read_response(ctx, res)
    local body_reader = res.body_reader
    if not body_reader then
        core.log.warn("AI service sent no response body")
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
                    goto CONTINUEFOR
                end

                local parts, err = ngx_re.split(event, ":", nil, nil, 2)
                if err then
                    core.log.warn("failed to split data event [", event,  "] to parts: ", err)
                    goto CONTINUEFOR
                end

                if #parts ~= 2 then
                    core.log.warn("malformed data event: ", event)
                    goto CONTINUEFOR
                end

                local data, err = core.json.decode(parts[2])
                if err then
                    core.log.warn("failed to decode data event [", parts[2], "] to json: ", err)
                    goto CONTINUEFOR
                end

                -- usage field is null for non-last events, null is parsed as userdata type
                if data and data.usage and type(data.usage) ~= "userdata" then
                    core.log.info("got token usage from ai service: ",
                                        core.json.delay_encode(data.usage))
                    ctx.ai_token_usage = {
                        prompt_tokens = data.usage.prompt_tokens or 0,
                        completion_tokens = data.usage.completion_tokens or 0,
                        total_tokens = data.usage.total_tokens or 0,
                    }
                end
                ::CONTINUEFOR::
            end

            ::CONTINUE::
        end
    end

    local raw_res_body, err = res:read_body()
    if not raw_res_body then
        core.log.warn("failed to read response body: ", err)
        if core.string.find(err, "timeout") then
            return 504
        end
        return 500
    end
    local res_body, err = core.json.decode(raw_res_body)
    if err then
        core.log.warn("invalid response body from ai service: ", raw_res_body, " err: ", err,
            ", it will cause token usage not available")
    else
        core.log.info("got token usage from ai service: ", core.json.delay_encode(res_body.usage))
        ctx.ai_token_usage = {
            prompt_tokens = res_body.usage and res_body.usage.prompt_tokens or 0,
            completion_tokens = res_body.usage and res_body.usage.completion_tokens or 0,
            total_tokens = res_body.usage and res_body.usage.total_tokens or 0,
        }
    end
    return res.status, raw_res_body
end


return _M
