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
local plugin = require("apisix.plugin")
local http = require("resty.http")
local proxy_upstream = require("apisix.proxy_upstream").proxy_upstream
local require = require
local schema = require("apisix.plugins.ai-rewrite.schema").schema
local pcall = pcall
local ngx = ngx
local req_set_body_data = ngx.req.set_body_data
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR


local plugin_name = "ai-response-rewrite"

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
    if not res then
        core.log.warn("failed to send request to AI service: ", err)
        if core.string.find(err, "timeout") then
            return 504
        end
        return internal_server_error
    end

    return ai_driver.read_response(ctx, res)
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
    ctx.lua_proxy_upstream = true
end


_M.before_proxy = function (conf, ctx)
    local status, res_body = proxy_upstream(conf, ctx)
    if not res_body then
        return status
    end
    return plugin.lua_body_filter(conf, ctx, res_body)
end

_M.lua_body_filter = function (conf, ctx, data)

    -- Prepare request for LLM service
    local ai_request_table = {
        messages = {
            {
                role = "system",
                content = conf.prompt
            },
            {
                role = "user",
                content = data
            }
        },
        stream = false
    }

    local status, res_body = request_to_llm(conf, ai_request_table, ctx)
    return status, res_body
end

return _M
