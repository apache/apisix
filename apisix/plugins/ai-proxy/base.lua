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

local ngx = ngx
local core = require("apisix.core")
local require = require
local pcall   = pcall
local exporter = require("apisix.plugins.prometheus.exporter")

local _M = {}

function _M.set_logging(ctx, summaries, payloads)
    if summaries then
        ctx.llm_summary = {
            request_model = ctx.var.request_llm_model,
            model = ctx.var.llm_model,
            duration = ctx.var.llm_time_to_first_token,
            prompt_tokens = ctx.var.llm_prompt_tokens,
            completion_tokens = ctx.var.llm_completion_tokens,
            upstream_response_time = ctx.var.apisix_upstream_response_time,
        }
    end
    if payloads then
        ctx.llm_request = {
            messages = ctx.var.llm_request_body and ctx.var.llm_request_body.messages,
            stream = ctx.var.request_type == "ai_stream"
        }
        ctx.llm_response_text = {
            content = ctx.var.llm_response_text
        }
    end
end


-- when on_error function is passed, before_proxy will keep on retrying until
-- on_error returns abort code
function _M.before_proxy(conf, ctx, on_error)
    while true do
        local ai_instance = ctx.picked_ai_instance
        local ai_driver = require("apisix.plugins.ai-drivers." .. ai_instance.provider)

        local is_claude = core.string.has_suffix(ctx.var.uri, "/v1/messages")
        if is_claude then
            ctx.ai_client_protocol = "claude"
        end

        local request_body, err = ai_driver.validate_request(ctx)
        if not request_body then
            return 400, err
        end

        local extra_opts = {
            name = ai_instance.name,
            endpoint = core.table.try_read_attr(ai_instance, "override", "endpoint"),
            model_options = ai_instance.options,
            conf = ai_instance.provider_conf or {},
            auth = ai_instance.auth,
        }

        if request_body.stream then
            request_body.stream_options = {
                include_usage = true
            }
            ctx.var.request_type = "ai_stream"
        else
            ctx.var.request_type = "ai_chat"
        end
        if request_body.model then
            ctx.var.request_llm_model = request_body.model
        end
        local model = ai_instance.options and ai_instance.options.model or request_body.model
        if model then
            ctx.var.llm_model = model
        end

        local do_request = function()
            ctx.llm_request_start_time = ngx.now()
            ctx.var.llm_request_body = request_body
            return ai_driver:request(ctx, conf, request_body, extra_opts)
        end

        exporter.inc_llm_active_connections(ctx)
        local ok, code_or_err, body = pcall(do_request)
        exporter.dec_llm_active_connections(ctx)
        if not ok then
            core.log.error("failed to send request to AI service: ", code_or_err)
            return 500
        end
        if code_or_err and on_error then
            local abort_code = on_error(ctx, conf, code_or_err)
            if abort_code then
                return abort_code, body
            end
        else
            return code_or_err, body
        end
    end
end


return _M
