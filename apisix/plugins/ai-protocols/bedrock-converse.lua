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

--- Bedrock Converse protocol adapter (client-side).
-- Handles detection and response parsing for the Amazon Bedrock
-- Converse API format. Non-streaming only in this phase.

local core = require("apisix.core")
local string_sub = string.sub
local type = type
local ipairs = ipairs
local table = table

local _M = {}


--- Detect whether the request matches the Bedrock Converse API format.
-- Uses URI suffix (/converse) and body (valid JSON table with messages).
function _M.matches(body, ctx)
    local uri = ctx.var and ctx.var.uri
    return uri and string_sub(uri, -9) == "/converse"
        and type(body) == "table" and type(body.messages) == "table"
end


--- Check whether the request is a streaming request.
-- Streaming is not supported in this phase.
function _M.is_streaming(body)
    return false
end


--- Prepare the outgoing request body for the target provider.
-- Remove fields Bedrock doesn't accept.
function _M.prepare_outgoing_request(body)
    body.stream = nil
end


--- Extract token usage from a non-streaming Bedrock response.
-- Bedrock format: res_body.usage.inputTokens / outputTokens / totalTokens
function _M.extract_usage(res_body)
    if type(res_body) ~= "table" or type(res_body.usage) ~= "table" then
        return nil, nil
    end
    local raw = res_body.usage
    return {
        prompt_tokens = raw.inputTokens or 0,
        completion_tokens = raw.outputTokens or 0,
        total_tokens = raw.totalTokens
            or (raw.inputTokens or 0) + (raw.outputTokens or 0),
    }, raw
end


--- Extract response text from a Bedrock Converse response.
-- Bedrock format: res_body.output.message.content[].text
function _M.extract_response_text(res_body)
    if type(res_body) ~= "table" then
        return nil
    end
    local message = res_body.output and res_body.output.message
    if type(message) ~= "table" or type(message.content) ~= "table" then
        return nil
    end
    local texts = {}
    for _, block in ipairs(message.content) do
        if type(block) == "table" and type(block.text) == "string" then
            core.table.insert(texts, block.text)
        end
    end
    if #texts > 0 then
        return table.concat(texts, " ")
    end
    return nil
end


--- Extract all text content from a request body for moderation.
function _M.extract_request_content(body)
    local contents = {}
    if type(body.system) == "table" then
        for _, block in ipairs(body.system) do
            if type(block) == "table" and type(block.text) == "string" then
                core.table.insert(contents, block.text)
            end
        end
    end
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            if type(message) ~= "table" then
                goto CONTINUE_MESSAGE
            end
            if type(message.content) == "table" then
                for _, block in ipairs(message.content) do
                    if type(block) == "table" and type(block.text) == "string" then
                        core.table.insert(contents, block.text)
                    end
                end
            end
            ::CONTINUE_MESSAGE::
        end
    end
    return contents
end


--- Get messages in canonical {role, content} format.
-- Bedrock content blocks [{text: "..."}] are flattened to plain text.
function _M.get_messages(body)
    local messages = {}
    if type(body.system) == "table" then
        local texts = {}
        for _, block in ipairs(body.system) do
            if type(block) == "table" and type(block.text) == "string" then
                core.table.insert(texts, block.text)
            end
        end
        if #texts > 0 then
            core.table.insert(messages, {
                role = "system",
                content = table.concat(texts, " "),
            })
        end
    end
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            if type(message) ~= "table" then
                goto CONTINUE
            end
            if type(message.content) == "table" then
                local texts = {}
                for _, block in ipairs(message.content) do
                    if type(block) == "table" and type(block.text) == "string" then
                        core.table.insert(texts, block.text)
                    end
                end
                if #texts > 0 then
                    core.table.insert(messages, {
                        role = message.role,
                        content = table.concat(texts, " "),
                    })
                end
            end
            ::CONTINUE::
        end
    end
    return messages
end


--- Prepend messages to the request body.
-- System messages go to body.system; user/assistant messages go to body.messages.
function _M.prepend_messages(body, msgs)
    if not msgs or #msgs == 0 then return end

    local new_system_blocks = {}
    local new_chat_messages = {}
    for _, msg in ipairs(msgs) do
        if msg.role == "system" then
            core.table.insert(new_system_blocks, {text = msg.content})
        else
            core.table.insert(new_chat_messages, {
                role = msg.role,
                content = {{text = msg.content}},
            })
        end
    end

    if #new_system_blocks > 0 then
        if type(body.system) ~= "table" then
            body.system = {}
        end
        local merged_system = {}
        for _, block in ipairs(new_system_blocks) do
            core.table.insert(merged_system, block)
        end
        for _, block in ipairs(body.system) do
            core.table.insert(merged_system, block)
        end
        body.system = merged_system
    end

    if #new_chat_messages > 0 then
        if type(body.messages) ~= "table" then
            body.messages = {}
        end
        local merged_messages = {}
        for _, msg in ipairs(new_chat_messages) do
            core.table.insert(merged_messages, msg)
        end
        for _, msg in ipairs(body.messages) do
            core.table.insert(merged_messages, msg)
        end
        body.messages = merged_messages
    end
end


--- Append messages to the request body.
-- System messages go to body.system; user/assistant messages go to body.messages.
function _M.append_messages(body, msgs)
    if not msgs or #msgs == 0 then return end

    for _, msg in ipairs(msgs) do
        if msg.role == "system" then
            if type(body.system) ~= "table" then
                body.system = {}
            end
            core.table.insert(body.system, {text = msg.content})
        else
            if type(body.messages) ~= "table" then
                body.messages = {}
            end
            core.table.insert(body.messages, {
                role = msg.role,
                content = {{text = msg.content}},
            })
        end
    end
end


--- Get raw request content for logging.
function _M.get_request_content(body)
    return body.messages
end


--- Build a non-streaming deny response in Bedrock Converse format.
function _M.build_deny_response(opts)
    return core.json.encode({
        output = {
            message = {
                role = "assistant",
                content = {{text = opts.text}},
            },
        },
        stopReason = "end_turn",
        usage = opts.usage,
    })
end


--- Build an empty usage object.
function _M.empty_usage()
    return { inputTokens = 0, outputTokens = 0, totalTokens = 0 }
end


--- Build a non-streaming request from system prompt and user content.
function _M.build_simple_request(system_prompt, user_content, opts)
    local body = {
        messages = {{
            role = "user",
            content = {{text = user_content}},
        }},
    }
    if system_prompt then
        body.system = {{text = system_prompt}}
    end
    if opts and opts.max_tokens then
        body.inferenceConfig = { maxTokens = opts.max_tokens }
    end
    return body
end


return _M
