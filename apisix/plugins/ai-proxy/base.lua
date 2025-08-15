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

local core = require("apisix.core")
local require = require
local bad_request = ngx.HTTP_BAD_REQUEST

local _M = {}

function _M.set_logging(ctx, summaries, payloads)
    if summaries then
        ctx.llm_summary = {
            model = ctx.var.llm_model,
            duration = ctx.var.llm_time_to_first_token,
            prompt_tokens = ctx.var.llm_prompt_tokens,
            completion_tokens = ctx.var.llm_completion_tokens,
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


function _M.before_proxy(conf, ctx)
    local ai_instance = ctx.picked_ai_instance
    local ai_driver = require("apisix.plugins.ai-drivers." .. ai_instance.provider)

    local request_body, err = ai_driver.validate_request(ctx)
    if not request_body then
        return bad_request, err
    end

    local extra_opts = {
        endpoint = core.table.try_read_attr(ai_instance, "override", "endpoint"),
        query_params = ai_instance.auth.query or {},
        headers = (ai_instance.auth.header or {}),
        model_options = ai_instance.options,
    }

    if request_body.stream then
        request_body.stream_options = {
            include_usage = true
        }
    end
    ctx.var.llm_request_body = request_body
    return ai_driver:request(ctx, conf, request_body, extra_opts)
end


return _M
