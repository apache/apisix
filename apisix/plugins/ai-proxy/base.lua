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

local CONTENT_TYPE_JSON = "application/json"
local core = require("apisix.core")
local bad_request = ngx.HTTP_BAD_REQUEST
local internal_server_error = ngx.HTTP_INTERNAL_SERVER_ERROR
local schema = require("apisix.plugins.ai-proxy.schema")
local ngx_req = ngx.req
local ngx_print = ngx.print
local ngx_flush = ngx.flush

local function keepalive_or_close(conf, httpc)
    if conf.set_keepalive then
        httpc:set_keepalive(10000, 100)
        return
    end
    httpc:close()
end

local _M = {}

function _M.new(proxy_request_to_llm_func, get_model_name_func)
    return function(conf, ctx)
        local ct = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
        if not core.string.has_prefix(ct, CONTENT_TYPE_JSON) then
            return bad_request, "unsupported content-type: " .. ct
        end

        local request_table, err = core.request.get_json_request_body_table()
        if not request_table then
            return bad_request, err
        end

        local ok, err = core.schema.check(schema.chat_request_schema, request_table)
        if not ok then
            return bad_request, "request format doesn't match schema: " .. err
        end

        request_table.model = get_model_name_func(conf)

        if core.table.try_read_attr(conf, "model", "options", "stream") then
            request_table.stream = true
        end

        local res, err, httpc = proxy_request_to_llm_func(conf, request_table, ctx)
        if not res then
            core.log.error("failed to send request to LLM service: ", err)
            return internal_server_error
        end

        local body_reader = res.body_reader
        if not body_reader then
            core.log.error("LLM sent no response body")
            return internal_server_error
        end

        if conf.passthrough then
            ngx_req.init_body()
            while true do
                local chunk, err = body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                ngx_req.append_body(chunk)
            end
            ngx_req.finish_body()
            keepalive_or_close(conf, httpc)
            return
        end

        if request_table.stream then
            while true do
                local chunk, err = body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                ngx_print(chunk)
                ngx_flush(true)
            end
            keepalive_or_close(conf, httpc)
            return
        else
            local res_body, err = res:read_body()
            if not res_body then
                core.log.error("failed to read response body: ", err)
                return internal_server_error
            end
            keepalive_or_close(conf, httpc)
            return res.status, res_body
        end
    end
end

return _M
