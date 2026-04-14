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
local ai_providers_schema = require("apisix.plugins.ai-providers.schema")
local protocols = require("apisix.plugins.ai-protocols")
local require = require
local pcall = pcall
local next = next
local type = type
local ngx = ngx
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local plugin_name = "ai-request-rewrite"

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
            description = "Model to execute. Examples: \"gpt-3.5-turbo\" for openai, " ..
            "\"deepseek-chat\" for deekseek, or \"qwen-turbo\" for openai-compatible services"
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
            enum = ai_providers_schema.providers,
        },
        auth = auth_schema,
        options = model_options_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 30000,
            description = "Total timeout in milliseconds for requests to LLM service, " ..
            "including connect, send, and read timeouts."
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

local function request_to_llm(conf, request_table, ctx, target_path)
    local ok, ai_provider = pcall(require, "apisix.plugins.ai-providers." .. conf.provider)
    if not ok then
        return nil, nil, "failed to load ai-provider: " .. conf.provider
    end

    local extra_opts = {
        endpoint = core.table.try_read_attr(conf, "override", "endpoint"),
        auth = conf.auth,
        model_options = conf.options,
        target_path = target_path,
    }
    ctx.llm_request_start_time = ngx.now()
    ctx.var.llm_request_body = request_table
    return ai_provider:request(ctx, conf, request_table, extra_opts)
end


local function get_provider_protocol(conf, ctx)
    local ok, ai_provider = pcall(require, "apisix.plugins.ai-providers." .. conf.provider)
    if not ok then
        return nil, nil, "failed to load provider: " .. conf.provider
    end
    local caps = ai_provider.capabilities or {}
    -- Prefer openai-chat as the common denominator
    local proto_name = caps["openai-chat"] and "openai-chat" or next(caps)
    if not proto_name then
        return nil, nil, "provider " .. conf.provider .. " has no capabilities"
    end

    local cap = caps[proto_name]
    local target_path
    if cap then
        local p = cap.path
        if type(p) == "function" then
            p = p(conf, ctx)
        end
        target_path = p
    end

    return protocols.get(proto_name), target_path
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
    local client_request_body, err = core.request.get_body()
    if err then
        core.log.warn("failed to get request body: ", err)
        return HTTP_BAD_REQUEST
    end

    if not client_request_body then
        core.log.warn("missing request body")
        return
    end

    -- Determine provider protocol
    local proto, target_path, proto_err = get_provider_protocol(conf, ctx)
    if not proto then
        core.log.error(proto_err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Build request in provider's native protocol format
    local ai_request_table = proto.build_simple_request(
        conf.prompt, client_request_body, conf.options)

    -- Send request to LLM service
    local status, raw_body, req_err = request_to_llm(conf, ai_request_table, ctx, target_path)

    if req_err then
        core.log.error("failed to request LLM: ", req_err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    if not status or status ~= 200 then
        core.log.error("LLM service returned error status: ", status)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Extract rewritten content from LLM response
    local response_table, decode_err = core.json.decode(raw_body)
    if not response_table then
        core.log.error("failed to decode LLM response: ", decode_err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local content = proto.extract_response_text(response_table)
    if not content then
        core.log.error("failed to extract text from LLM response")
        return HTTP_INTERNAL_SERVER_ERROR
    end

    -- Replace the original request body with the rewritten content
    ngx.req.set_body_data(content)
end

return _M
