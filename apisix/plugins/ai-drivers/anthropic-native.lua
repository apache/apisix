--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements. See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License. You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core = require("apisix.core" )
local cjson = require("cjson.safe")
local shared = require("apisix.plugins.ai-drivers.shared")
local sse = require("apisix.plugins.ai-drivers.sse")

local _M = {
    version = 0.1,
    priority = 100,
    name = "anthropic-native",
    host = "api.anthropic.com",
    path = "/v1/messages",
    port = 443,
}

local ANTHROPIC_VERSION = "2023-06-01"
local DEFAULT_MAX_TOKENS = 2048

-- Map Anthropic stop reason to OpenAI finish reason
local FINISH_REASON_MAP = {
    ["end_turn"] = "stop",
    ["max_tokens"] = "length",
    ["stop_sequence"] = "stop",
    ["tool_use"] = "tool_calls",
}

-- Convert OpenAI-like messages to Anthropic Messages API format.
-- Anthropic requires:
-- 1. System prompt in a separate "system" field.
-- 2. Messages must strictly alternate between "user" and "assistant".
local function convert_messages(openai_messages)
    local anthropic_messages = {}
    local system_prompt = nil

    for _, msg in ipairs(openai_messages) do
        if msg.role == "system" then
            -- Anthropic requires system prompt to be a top-level field
            if not system_prompt then
                system_prompt = msg.content
            else
                -- Handle multiple system prompts by concatenating or ignoring
                -- For simplicity, we take the first one and log a warning
                core.log.warn("Multiple system prompts found, only the first one is used for Anthropic.")
            end
        else
            -- Anthropic uses "user" and "assistant" roles
            local role = msg.role
            if role == "function" or role == "tool" then
                -- Anthropic does not have a direct "tool" role in the same way.
                -- For basic chat completion, we can skip or convert to user message.
                -- For simplicity, we skip tool-related messages for now,
                -- as full tool-use support requires more complex logic.
                core.log.warn("Skipping tool/function message for Anthropic native driver.")
            else
                table.insert(anthropic_messages, {
                    role = role,
                    content = msg.content,
                })
            end
        end
    end

    return anthropic_messages, system_prompt
end

-- Rewrite the request from OpenAI-compatible format to Anthropic Messages API format.
function _M.rewrite_request(conf, ctx)
    local openai_req = ctx.var.json_body
    if not openai_req then
        return core.response.exit(400, {message = "Invalid JSON body"})
    end

    local anthropic_messages, system_prompt = convert_messages(openai_req.messages or {})

    local anthropic_req = {
        model = openai_req.model,
        messages = anthropic_messages,
        -- Anthropic requires max_tokens_to_sample or max_tokens. We use max_tokens.
        max_tokens = openai_req.max_tokens or DEFAULT_MAX_TOKENS,
        stream = openai_req.stream,
        temperature = openai_req.temperature,
        top_p = openai_req.top_p,
        top_k = openai_req.top_k, -- Anthropic specific parameter
    }

    if system_prompt then
        anthropic_req.system = system_prompt
    end

    -- Set Anthropic specific headers
    core.request.set_header("anthropic-version", ANTHROPIC_VERSION)
    core.request.set_header("Content-Type", "application/json")

    -- Set new request body
    local new_body = cjson.encode(anthropic_req)
    core.request.set_body(new_body)

    -- Set upstream host and path
    ctx.var.upstream_host = _M.host
    ctx.var.upstream_uri = _M.path

    return true
end

-- Process the non-streaming response from Anthropic to OpenAI-compatible format.
function _M.process_response(conf, ctx)
    local anthropic_resp = ctx.var.json_body
    if not anthropic_resp or anthropic_resp.type ~= "message" then
        return core.response.exit(500, {message = "Invalid Anthropic response format"})
    end

    local content = anthropic_resp.content[1]
    local text = content and content.text or ""
    local finish_reason = FINISH_REASON_MAP[anthropic_resp.stop_reason] or "stop"

    local openai_resp = {
        id = anthropic_resp.id,
        object = "chat.completion",
        created = core.time(),
        model = anthropic_resp.model,
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = text,
                },
                finish_reason = finish_reason,
            },
        },
        usage = {
            prompt_tokens = anthropic_resp.usage.input_tokens,
            completion_tokens = anthropic_resp.usage.output_tokens,
            total_tokens = anthropic_resp.usage.input_tokens + anthropic_resp.usage.output_tokens,
        },
    }

    local new_body = cjson.encode(openai_resp)
    core.response.set_header("Content-Type", "application/json")
    core.response.set_body(new_body)

    return true
end

-- Process the streaming response from Anthropic to OpenAI-compatible format.
function _M.process_stream(conf, ctx)
    local anthropic_stream = ctx.var.stream_data
    local openai_stream = {}
    local model = ""
    local id = ""
    local created = core.time()

    for _, event in ipairs(anthropic_stream) do
        local event_type = event.event
        local data = event.data

        if event_type == "message_start" then
            -- Extract initial info from message_start event
            local message = data.message
            model = message.model
            id = message.id
        elseif event_type == "content_block_delta" then
            -- Stream text content
            local delta = data.delta
            if delta.type == "text_delta" then
                local chunk = shared.create_stream_chunk(id, created, model, delta.text)
                table.insert(openai_stream, chunk)
            end
        elseif event_type == "message_stop" then
            -- Stream stop reason
            local reason = data.stop_reason
            local finish_reason = FINISH_REASON_MAP[reason] or "stop"
            local chunk = shared.create_stream_chunk(id, created, model, nil, finish_reason)
            table.insert(openai_stream, chunk)
        end
    end

    -- Send the converted stream data
    for _, chunk in ipairs(openai_stream) do
        sse.send_chunk(chunk)
    end

    return true
end

return _M
