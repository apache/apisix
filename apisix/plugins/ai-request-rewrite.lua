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
local schema = require("apisix.plugins.ai-rewrite.schema").schema
local require = require
local pcall = pcall
local ngx = ngx
local req_set_body_data = ngx.req.set_body_data
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR

local plugin_name = "ai-request-rewrite"

local _M = {
    version = 0.1,
    priority = 1073,
    name = plugin_name,
    schema = schema
}

local function request_to_llm(conf, request_table, ctx)
    local ok, ai_driver = pcall(require, "apisix.plugins.ai-drivers." .. conf.provider)
    if not ok then
        return nil, nil, "failed to load ai-driver: " .. conf.provider
    end

    local extra_opts = {
        endpoint = core.table.try_read_attr(conf, "override", "endpoint"),
        query_params = conf.auth.query or {},
        headers = (conf.auth.header or {}),
        model_options = conf.options
    }

    local res, err = ai_driver:request(conf, request_table, extra_opts)
    if err then
        return nil, nil, err
    end

    local resp_body, err = res:read_body()
    if err then
        return nil, nil, err
    end

    return res, resp_body
end


local function parse_llm_response(res_body)
    local response_table, err = core.json.decode(res_body)

    if err then
        return nil, "failed to decode llm response " .. ", err: " .. err
    end

    if not response_table.choices or not response_table.choices[1] then
        return nil, "'choices' not in llm response"
    end

    local message = response_table.choices[1].message
    if not message then
        return nil, "'message' not in llm response choices"
    end

    return message.content
end


function _M.check_schema(conf)
    -- openai-compatible should be used with override.endpoint
    if conf.provider == "openai-compatible" then
        local override = conf.override

        if not override or not override.endpoint then
            return false, "override.endpoint is required for openai-compatible provider"
        end
    end

    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    ctx.proxy_nginx_upstream = true
    local client_request_body, err = core.request.get_body()
    if err then
        core.log.warn("failed to get request body: ", err)
        return HTTP_BAD_REQUEST
    end

    if not client_request_body then
        core.log.warn("missing request body")
        return
    end

    -- Prepare request for LLM service
    local ai_request_table = {
        messages = {
            {
                role = "system",
                content = conf.prompt
            },
            {
                role = "user",
                content = client_request_body
            }
        },
        stream = false
    }

    -- Send request to LLM service
    local res, resp_body, err = request_to_llm(conf, ai_request_table, ctx)
    if err then
        core.log.error("failed to request to LLM service: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Handle LLM response
    if res.status > 299 then
        core.log.error("LLM service returned error status: ", res.status)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Parse LLM response
    local llm_response, err = parse_llm_response(resp_body)
    if err then
        core.log.error("failed to parse LLM response: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    req_set_body_data(llm_response)
end

return _M
