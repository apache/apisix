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
local bad_request = ngx.HTTP_BAD_REQUEST

local _M = {}

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
        ctx.var.request_type = "ai_stream"
    else
        ctx.var.request_type = "ai_chat"
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
    return code_or_err, body
end


return _M
