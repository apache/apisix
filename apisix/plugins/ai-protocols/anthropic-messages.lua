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

--- Anthropic Messages protocol adapter (client-side).
-- Handles detection and response parsing for the Anthropic Messages API
-- format. This adapter is for clients sending Anthropic-format requests.
--
-- Conversion logic (Anthropic↔OpenAI) lives in
-- ai-protocols/converters/anthropic-messages-to-openai-chat.lua.

local core = require("apisix.core")
local string_sub = string.sub
local uuid = require("resty.jit-uuid")
local sse = require("apisix.plugins.ai-transport.sse")
local table = table
local type = type
local ipairs = ipairs

local _M = {}


--- Detect whether the request matches the Anthropic Messages API format.
-- Uses URI suffix (/v1/messages) and body (valid JSON table).
function _M.matches(body, ctx)
    local uri = ctx.var and ctx.var.uri
    return uri and string_sub(uri, -12) == "/v1/messages" and type(body) == "table"
end


--- Check whether the request is a streaming request.
function _M.is_streaming(body)
    return body.stream == true
end


--- Prepare the request body for sending.
-- Anthropic protocol delegates to the converter for stream_options —
-- the converter module knows what the target provider needs.
function _M.prepare_request(body, ctx, opts)
    return body, body.model
end


--- Parse a streaming SSE event in native Anthropic format.
-- Used when the provider natively supports Anthropic protocol.
function _M.parse_sse_event(event, ctx, state)
    if event.type == "content_block_delta" then
        local data, err = core.json.decode(event.data)
        if not data then
            core.log.warn("failed to decode SSE data: ", err)
            return { type = "skip" }
        end
        if type(data.delta) == "table" and data.delta.type == "text_delta"
                and type(data.delta.text) == "string" then
            return {
                type = "delta",
                texts = { data.delta.text },
            }
        end
        return { type = "skip" }

    elseif event.type == "message_delta" then
        local data, err = core.json.decode(event.data)
        if not data then
            core.log.warn("failed to decode message_delta: ", err)
            return { type = "skip" }
        end
        if type(data.usage) == "table" then
            return {
                type = "usage",
                usage = {
                    prompt_tokens = data.usage.input_tokens or 0,
                    completion_tokens = data.usage.output_tokens or 0,
                    total_tokens = (data.usage.input_tokens or 0)
                        + (data.usage.output_tokens or 0),
                },
                raw_usage = data.usage,
            }
        end
        return { type = "skip" }

    elseif event.type == "message_stop" then
        return { type = "done" }

    elseif event.type == "message_start" then
        local data = core.json.decode(event.data)
        if not data then
            return { type = "skip" }
        end
        if type(data.message) == "table" and type(data.message.usage) == "table" then
            local usage = data.message.usage
            return {
                type = "usage",
                usage = {
                    prompt_tokens = usage.input_tokens or 0,
                    completion_tokens = usage.output_tokens or 0,
                    total_tokens = (usage.input_tokens or 0) + (usage.output_tokens or 0),
                },
                raw_usage = usage,
            }
        end
        return { type = "skip" }

    elseif event.type == "error" then
        local err_data = core.json.decode(event.data)
        local err_type = err_data and err_data.error and err_data.error.type or "unknown"
        local err_msg = err_data and err_data.error and err_data.error.message or "unknown"
        core.log.warn("Anthropic SSE error: type=", err_type, ", message=", err_msg)
        return { type = "done" }
    end

    return { type = "skip" }
end


--- Extract response text from a native Anthropic response body.
function _M.extract_response_text(res_body)
    if type(res_body) ~= "table" then
        return nil
    end
    if type(res_body.content) == "table" then
        local contents = {}
        for _, block in ipairs(res_body.content) do
            if type(block) == "table" and block.type == "text"
                    and type(block.text) == "string" then
                core.table.insert(contents, block.text)
            end
        end
        if #contents > 0 then
            return table.concat(contents, " ")
        end
    end
    return nil
end


--- Build a non-streaming request from system prompt and user content.
function _M.build_simple_request(system_prompt, user_content, opts)
    local body = {
        messages = {{role = "user", content = user_content}},
        stream = false,
        max_tokens = (opts and opts.max_tokens) or 4096,
    }
    if system_prompt then
        body.system = system_prompt
    end
    if opts and opts.model then
        body.model = opts.model
    end
    return body
end


function _M.extract_usage(res_body)
    if type(res_body) ~= "table" or type(res_body.usage) ~= "table" then
        return nil, nil
    end
    local raw = res_body.usage
    local prompt = raw.input_tokens or 0
    local completion = raw.output_tokens or 0
    return {
        prompt_tokens = prompt,
        completion_tokens = completion,
        total_tokens = prompt + completion,
    }, raw
end


--- Extract all text content from a request body for moderation.
function _M.extract_request_content(body)
    local contents = {}
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            if type(message) ~= "table" then
                goto CONTINUE_MESSAGE
            end
            if type(message.content) == "string" then
                core.table.insert(contents, message.content)
            elseif type(message.content) == "table" then
                for _, block in ipairs(message.content) do
                    if type(block) == "table" and block.type == "text"
                            and type(block.text) == "string" then
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
-- Anthropic content blocks are flattened to plain text.
function _M.get_messages(body)
    local messages = {}
    if type(body.system) == "string" then
        core.table.insert(messages, {role = "system", content = body.system})
    end
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            local content = message.content
            if type(content) == "string" then
                core.table.insert(messages, {role = message.role, content = content})
            elseif type(content) == "table" then
                local texts = {}
                for _, block in ipairs(content) do
                    if type(block) == "table" and block.type == "text" then
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
        end
    end
    return messages
end


--- Prepend messages to the request body.
function _M.prepend_messages(body, msgs)
    if not msgs or #msgs == 0 then return end
    if not body.messages then
        body.messages = {}
    end
    local new_messages = {}
    for _, msg in ipairs(msgs) do
        core.table.insert(new_messages, {role = msg.role, content = msg.content})
    end
    for _, msg in ipairs(body.messages) do
        core.table.insert(new_messages, msg)
    end
    body.messages = new_messages
end


--- Append messages to the request body.
function _M.append_messages(body, msgs)
    if not msgs or #msgs == 0 then return end
    if not body.messages then
        body.messages = {}
    end
    for _, msg in ipairs(msgs) do
        core.table.insert(body.messages, {role = msg.role, content = msg.content})
    end
end


--- Get raw request content for logging.
function _M.get_request_content(body)
    return body.messages
end
-- opts: {text, model, usage, stream}
function _M.build_deny_response(opts)
    if opts.stream then
        local message_start = {
            type = "message_start",
            message = {
                id = uuid.generate_v4(),
                type = "message",
                role = "assistant",
                model = opts.model,
                content = {},
                usage = opts.usage,
            },
        }
        local content_block_start = {
            type = "content_block_start",
            index = 0,
            content_block = { type = "text", text = "" },
        }
        local content_block_delta = {
            type = "content_block_delta",
            index = 0,
            delta = { type = "text_delta", text = opts.text },
        }
        local content_block_stop = {
            type = "content_block_stop",
            index = 0,
        }
        local message_delta = {
            type = "message_delta",
            delta = { stop_reason = "end_turn" },
            usage = opts.usage,
        }
        return sse.encode({ type = "message_start", data = core.json.encode(message_start) })
            .. "\n"
            .. sse.encode({ type = "content_block_start",
                            data = core.json.encode(content_block_start) })
            .. "\n"
            .. sse.encode({ type = "content_block_delta",
                            data = core.json.encode(content_block_delta) })
            .. "\n"
            .. sse.encode({ type = "content_block_stop",
                            data = core.json.encode(content_block_stop) })
            .. "\n"
            .. sse.encode({ type = "message_delta",
                            data = core.json.encode(message_delta) })
            .. "\n"
            .. sse.encode({ type = "message_stop", data = "{}" })
    else
        return core.json.encode({
            id = uuid.generate_v4(),
            type = "message",
            role = "assistant",
            model = opts.model,
            content = {{
                type = "text",
                text = opts.text,
            }},
            stop_reason = "end_turn",
            usage = opts.usage,
        })
    end
end


--- Build an empty usage object.
function _M.empty_usage()
    return { input_tokens = 0, output_tokens = 0 }
end


--- Check if an SSE event is a data event (contains parseable content).
function _M.is_data_event(event)
    return event.type == "content_block_delta" or event.type == "message_delta"
end


--- Check if an SSE event is the terminal/done event.
function _M.is_done_event(event)
    return event.type == "message_stop"
end


--- Build a terminal SSE event string.
function _M.build_done_event()
    return sse.encode({ type = "message_stop", data = "{}" })
end


return _M
