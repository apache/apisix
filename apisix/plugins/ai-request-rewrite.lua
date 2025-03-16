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
local ngx = ngx

local require = require

local plugin_name = "ai-request-rewrite"

local bad_request = ngx.HTTP_BAD_REQUEST
local internal_server_error = ngx.HTTP_INTERNAL_SERVER_ERROR


local auth_item_schema = {
    type = "object",
    patternProperties = {
        ["^[a-zA-Z0-9._-]+$"] = {
            type = "string"
        }
    }
}

local auth_schema = {
    type = "object",
    properties = {
        header = auth_item_schema,
        query = auth_item_schema
    },
    additionalProperties = false
}

local model_options_schema = {
    description = "Key/value settings for the model",
    type = "object",
    properties = {
        model = {
            type = "string",
            description = "Model to execute. Examples: \"gpt-3.5-turbo\" for openai, \"deepseek-chat\" for deekseek, or \"qwen-turbo\" for openai-compatible services"
        }
    },
    additionalProperties = true
}

local schema = {
    type = "object",
    properties = {
        prompt = {
            type = "string",
            description = "The prompt to rewrite client request."
        },
        provider = {
            type = "string",
            description = "Name of the AI service provider.",
            enum = {"openai", "openai-compatible", "deepseek"} -- add more providers later
        },
        auth = auth_schema,
        options = model_options_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 30000,
            description = "timeout in milliseconds"
        },
        keepalive = {
            type = "boolean",
            default = true
        },
        keepalive_pool = {
            type = "integer",
            minimum = 1,
            default = 30
        },
        ssl_verify = {
            type = "boolean",
            default = true
        },
        override = {
            type = "object",
            properties = {
                endpoint = {
                    type = "string",
                    description = "To be specified to override " ..
                    "the endpoint of the AI service provider."
                }
            }
        }
    },
    required = {"prompt", "provider", "auth"}
}

local _M = {
    version = 0.1,
    priority = 1073,
    name = plugin_name,
    schema = schema
}

local function proxy_request_to_llm(conf, request_table, ctx)
    local ai_driver = require("apisix.plugins.ai-drivers." .. conf.provider)

    local extra_opts = {
        endpoint = core.table.try_read_attr(conf, "override", "endpoint"),
        query_params = conf.auth.query or {},
        headers = (conf.auth.header or {}),
        model_options = conf.options
    }

    local res, err, httpc = ai_driver:request(conf, request_table, extra_opts)

    if not res then return nil, err, nil end
    return res, nil, httpc
end


local function parse_llm_response(res_body)
    local response_table, err = core.json.decode(res_body)

    if not response_table then 
        return nil, "failed to decode llm response " .. ", err: " .. err
    end

    if not response_table.choices then
        return nil, "'choices' not in llm response"
    end

    local message = response_table.choices[1].message
    if not message then
        return nil, "'message' not in llm response choices"
    end

    return message.content, nil
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
    local client_request_table, err = core.request.get_body()
    if not client_request_table then
        core.log.error("failed to get request body: ", err)
        return bad_request, err
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
                content = client_request_table
            }
        },
        stream = false
    }

    -- Send request to LLM service
    local res, err, httpc = proxy_request_to_llm(conf, ai_request_table, ctx)
    if not res then
        core.log.error("failed to send request to LLM service: ", err)
        return internal_server_error
    end

    -- Handle LLM response
    if res.status >= 400 then
        core.log.error("LLM service returned error status: ", res.status, ", err: ", err)
        return internal_server_error
    end

    -- Read response body
    local res_body, err = res:read_body()
    if not res_body then
        core.log.error("failed to read LLM response body: ", err)
        httpc:close()
        return internal_server_error
    end

    -- Parse LLM response
    local llm_response, err = parse_llm_response(res_body)
    if not llm_response then
        core.log.error("failed to parse LLM response: ", err)
        httpc:close()
        return internal_server_error
    end

    httpc:close()
    ngx.req.set_body_data(llm_response)
end

return _M
