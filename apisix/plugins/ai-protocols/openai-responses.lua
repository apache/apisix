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

--- OpenAI Responses API protocol adapter.
-- Handles the Responses API format with its different SSE event model
-- and response structure (output[] instead of choices[]).

local core = require("apisix.core")
local uuid = require("resty.jit-uuid")
local sse = require("apisix.plugins.ai-transport.sse")
local type = type
local ipairs = ipairs
local table = table
local string_sub = string.sub

local _M = {}


--- Detect whether the request matches OpenAI Responses API format.
-- Requires URI suffix (/v1/responses) and body (has input field).
function _M.matches(body, ctx)
    local uri = ctx.var and ctx.var.uri
    return uri and string_sub(uri, -13) == "/v1/responses"
        and type(body) == "table" and body.input ~= nil
end


--- Check whether the request is a streaming request.
function _M.is_streaming(body)
    return body.stream == true
end



function _M.parse_sse_event(event, ctx, state)
    if event.type == "response.output_text.delta" then
        local data, err = core.json.decode(event.data)
        if not data then
            core.log.warn("failed to decode SSE data: ", err)
            return { type = "skip" }
        end
        if type(data.delta) == "string" then
            return {
                type = "delta",
                texts = { data.delta },
            }
        end
        return { type = "skip" }

    elseif event.type == "response.completed" then
        local result = { type = "done" }
        local data, err = core.json.decode(event.data)
        if not data then
            core.log.warn("failed to decode response.completed SSE data: ", err)
            return result
        end
        if type(data.response) == "table"
                and type(data.response.usage) == "table" then
            local usage = data.response.usage
            result.type = "usage_and_done"
            result.usage = {
                prompt_tokens = usage.input_tokens or 0,
                completion_tokens = usage.output_tokens or 0,
                total_tokens = usage.total_tokens or 0,
            }
            result.raw_usage = usage
        end
        return result

    elseif event.type == "response.failed"
            or event.type == "response.incomplete"
            or event.type == "error" then
        return { type = "done" }
    end

    -- All other Responses API events are silently passed through
    return { type = "skip" }
end


function _M.extract_response_text(res_body)
    if type(res_body.output) ~= "table" then
        return nil
    end
    local texts = {}
    for _, item in ipairs(res_body.output) do
        if type(item) == "table" and item.type == "message"
                and type(item.content) == "table" then
            for _, part in ipairs(item.content) do
                if part.type == "output_text" and type(part.text) == "string" then
                    core.table.insert(texts, part.text)
                end
            end
        end
    end
    if #texts > 0 then
        return table.concat(texts, " ")
    end
    return nil
end


--- Build a non-streaming request from system prompt and user content.
function _M.build_simple_request(system_prompt, user_content, opts)
    local body = {
        input = user_content,
        stream = false,
    }
    if system_prompt then
        body.instructions = system_prompt
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
    -- Responses API uses input_tokens / output_tokens
    local prompt = raw.input_tokens or 0
    local completion = raw.output_tokens or 0
    return {
        prompt_tokens = prompt,
        completion_tokens = completion,
        total_tokens = raw.total_tokens or (prompt + completion),
    }, raw
end


--- Extract all text content from a request body for moderation.
function _M.extract_request_content(body)
    local contents = {}
    local input = body.input
    if type(input) == "string" then
        core.table.insert(contents, input)
    elseif type(input) == "table" then
        for _, item in ipairs(input) do
            if type(item) == "string" then
                core.table.insert(contents, item)
            elseif type(item) == "table" and item.content then
                if type(item.content) == "string" then
                    core.table.insert(contents, item.content)
                elseif type(item.content) == "table" then
                    for _, part in ipairs(item.content) do
                        if type(part) == "table" and part.text then
                            core.table.insert(contents, part.text)
                        end
                    end
                end
            end
        end
    end
    if body.instructions then
        core.table.insert(contents, body.instructions)
    end
    return contents
end


--- Get messages in canonical {role, content} format.
-- Converts instructions + input into messages-style list.
function _M.get_messages(body)
    local messages = {}
    if type(body.instructions) == "string" then
        core.table.insert(messages, {role = "system", content = body.instructions})
    end
    local input = body.input
    if type(input) == "string" then
        core.table.insert(messages, {role = "user", content = input})
    elseif type(input) == "table" then
        for _, item in ipairs(input) do
            if type(item) == "string" then
                core.table.insert(messages, {role = "user", content = item})
            elseif type(item) == "table" then
                local role = item.role or "user"
                local content = item.content or item.text
                if type(content) == "string" then
                    core.table.insert(messages, {role = role, content = content})
                end
            end
        end
    end
    return messages
end


--- Prepend messages to the request body.
-- System messages go to instructions; user messages prepend to input.
function _M.prepend_messages(body, msgs)
    if not msgs or #msgs == 0 then return end
    local parts = {}
    for _, msg in ipairs(msgs) do
        core.table.insert(parts, msg.content)
    end
    local prepend_text = table.concat(parts, "\n")
    if type(body.instructions) == "string" then
        body.instructions = prepend_text .. "\n" .. body.instructions
    else
        body.instructions = prepend_text
    end
end


--- Append messages to the request body.
function _M.append_messages(body, msgs)
    if not msgs or #msgs == 0 then return end
    local parts = {}
    for _, msg in ipairs(msgs) do
        core.table.insert(parts, msg.content)
    end
    local append_text = table.concat(parts, "\n")
    if type(body.input) == "string" then
        body.input = body.input .. "\n" .. append_text
    elseif type(body.input) == "table" then
        core.table.insert(body.input, {
            type = "message",
            role = "user",
            content = append_text,
        })
    else
        body.input = append_text
    end
end


--- Get raw request content for logging.
function _M.get_request_content(body)
    return body.input
end
-- opts: {text, model, usage, stream}
function _M.build_deny_response(opts)
    local response_obj = {
        id = uuid.generate_v4(),
        object = "response",
        status = "completed",
        model = opts.model,
        output = {{
            type = "message",
            role = "assistant",
            content = {{
                type = "output_text",
                text = opts.text,
            }},
        }},
        usage = opts.usage,
    }
    if opts.stream then
        local delta_event = {
            type = "response.output_text.delta",
            delta = opts.text,
        }
        local completed_event = {
            type = "response.completed",
            response = response_obj,
        }
        return "event: response.output_text.delta\n"
            .. "data: " .. core.json.encode(delta_event) .. "\n\n"
            .. "event: response.completed\n"
            .. "data: " .. core.json.encode(completed_event) .. "\n\n"
    else
        return core.json.encode(response_obj)
    end
end


--- Build an empty usage object.
function _M.empty_usage()
    return { input_tokens = 0, output_tokens = 0, total_tokens = 0 }
end


--- Check if an SSE event is a data event.
function _M.is_data_event(event)
    return event.type == "response.completed"
end


--- Check if an SSE event is the terminal/done event.
function _M.is_done_event(event)
    return event.type == "response.completed"
end


--- Build a terminal SSE event string.
function _M.build_done_event()
    return sse.encode({
        type = "response.completed",
        data = core.json.encode({
            type = "response.completed",
            response = { status = "completed", output = {} }
        })
    })
end


return _M
