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

--- OpenAI Chat Completions protocol adapter.
-- This is the default/fallback adapter — no conversion needed since
-- the internal format matches OpenAI Chat Completions.

local core = require("apisix.core")
local uuid = require("resty.jit-uuid")
local table = table
local type = type
local ipairs = ipairs

local _M = {}


--- Detect whether the request body matches OpenAI Chat Completions format.
-- Body-only detection: matches any request with a messages array.
function _M.matches(body, ctx)
    return type(body) == "table" and type(body.messages) == "table"
end


--- Check whether the request is a streaming request.
function _M.is_streaming(body)
    return body.stream == true
end


--- Prepare the outgoing request body for the target provider.
-- Injects stream_options so the provider includes usage in streaming responses.
-- Called after protocol conversion in build_request(), covering both passthrough
-- and convert scenarios.
function _M.prepare_outgoing_request(body)
    if body.stream then
        body.stream_options = { include_usage = true }
        return true
    end
    return false
end


--- Parse a streaming SSE event and extract content/usage/done signals.
-- @param event table SSE event {type, data}
-- @param ctx table Request context
-- @param state table Mutable state for tracking across events
-- @return table|nil Parsed result {type="delta"|"usage"|"done"|"skip", ...}
function _M.parse_sse_event(event, ctx, state)
    if event.type == "message" then
        if type(event.data) ~= "string" or event.data:match("^%s*$") then
            return { type = "skip" }
        end

        -- OpenAI signals stream end with data: [DONE] (no event: line,
        -- so it arrives with the default type "message")
        if event.data == "[DONE]" then
            return { type = "done" }
        end

        local data, err = core.json.decode(event.data, { null_as_nil = true })
        if not data then
            core.log.warn("failed to decode SSE data: ", err)
            return { type = "skip" }
        end

        local result = { type = "delta", data = data }

        -- Extract text content and detect tool calls from choices
        if type(data.choices) == "table" and #data.choices > 0 then
            local texts = {}
            for _, choice in ipairs(data.choices) do
                if type(choice) == "table" and type(choice.delta) == "table" then
                    if type(choice.delta.content) == "string" then
                        core.table.insert(texts, choice.delta.content)
                    end
                    if type(choice.delta.tool_calls) == "table"
                            and #choice.delta.tool_calls > 0 then
                        result.has_tool_call = true
                    end
                end
            end
            if #texts > 0 then
                result.texts = texts
            end
        end

        -- Extract usage (null for non-final chunks; cjson decodes null as userdata)
        if type(data.usage) == "table" then
            local u = data.usage
            local pd = type(u.prompt_tokens_details) == "table" and u.prompt_tokens_details
            local cd = type(u.completion_tokens_details) == "table" and u.completion_tokens_details
            result.type = "usage"
            result.usage = {
                prompt_tokens = u.prompt_tokens or 0,
                completion_tokens = u.completion_tokens or 0,
                total_tokens = u.total_tokens or 0,
                cache_read_input_tokens = pd and pd.cached_tokens
                                          or u.prompt_cache_hit_tokens or 0,
                cache_creation_input_tokens = pd and pd.cache_creation_input_tokens or 0,
                reasoning_tokens = cd and cd.reasoning_tokens or 0,
            }
            result.raw_usage = u
        end

        return result
    end

    return { type = "skip" }
end


--- Extract response text from a non-streaming response body.
-- @param res_body table Parsed response JSON
-- @return string|nil The extracted text content
function _M.extract_response_text(res_body)
    if type(res_body) ~= "table" then
        return nil
    end
    if type(res_body.choices) == "table" and #res_body.choices > 0 then
        local contents = {}
        for _, choice in ipairs(res_body.choices) do
            if type(choice) == "table"
                    and type(choice.message) == "table"
                    and type(choice.message.content) == "string" then
                core.table.insert(contents, choice.message.content)
            end
        end
        return table.concat(contents, " ")
    end
    return nil
end


--- Build a non-streaming request from system prompt and user content.
function _M.build_simple_request(system_prompt, user_content, opts)
    local body = {
        messages = {},
        stream = false,
    }
    if system_prompt then
        core.table.insert(body.messages, {role = "system", content = system_prompt})
    end
    core.table.insert(body.messages, {role = "user", content = user_content})
    if opts and opts.model then
        body.model = opts.model
    end
    return body
end


--- Extract usage from a non-streaming response body.
-- @param res_body table Parsed response JSON
-- @return table|nil Usage table {prompt_tokens, completion_tokens, total_tokens}
-- @return table|nil Raw usage from provider
function _M.extract_usage(res_body)
    if type(res_body) ~= "table" or type(res_body.usage) ~= "table" then
        return nil, nil
    end
    local raw = res_body.usage
    local pdetails = type(raw.prompt_tokens_details) == "table" and raw.prompt_tokens_details
    local cdetails = type(raw.completion_tokens_details) == "table"
                     and raw.completion_tokens_details
    -- OpenAI uses prompt_tokens_details.cached_tokens; DeepSeek uses prompt_cache_hit_tokens
    local cache_read = pdetails and pdetails.cached_tokens or raw.prompt_cache_hit_tokens or 0
    return {
        prompt_tokens = raw.prompt_tokens or 0,
        completion_tokens = raw.completion_tokens or 0,
        total_tokens = raw.total_tokens or (raw.prompt_tokens or 0) + (raw.completion_tokens or 0),
        cache_read_input_tokens = cache_read,
        cache_creation_input_tokens = pdetails and pdetails.cache_creation_input_tokens or 0,
        reasoning_tokens = cdetails and cdetails.reasoning_tokens or 0,
    }, raw
end


--- Detect whether a non-streaming response contains tool calls.
function _M.has_tool_call(res_body)
    if type(res_body) ~= "table" or type(res_body.choices) ~= "table" then
        return false
    end
    for _, choice in ipairs(res_body.choices) do
        if type(choice) == "table" and type(choice.message) == "table"
                and type(choice.message.tool_calls) == "table"
                and #choice.message.tool_calls > 0 then
            return true
        end
    end
    return false
end


--- Extract the end-user identifier from a request body.
function _M.extract_end_user_id(body)
    if type(body) ~= "table" then
        return nil
    end
    if type(body.safety_identifier) == "string" then
        return body.safety_identifier
    end
    if type(body.user) == "string" then
        return body.user
    end
    return nil
end


-- Append a single message's text (string content or text parts) into `contents`.
local function append_message_text(contents, message)
    if type(message) ~= "table" then
        return
    end
    if type(message.content) == "string" then
        core.table.insert(contents, message.content)
    elseif type(message.content) == "table" then
        for _, part in ipairs(message.content) do
            if type(part) == "table" and part.type == "text"
                    and type(part.text) == "string" then
                core.table.insert(contents, part.text)
            end
        end
    end
end


--- Extract all text content from a request body for moderation.
function _M.extract_request_content(body)
    local contents = {}
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            append_message_text(contents, message)
        end
    end
    return contents
end


local function is_turn_role(message, roles)
    return type(message) == "table" and message.role ~= nil and roles[message.role]
end


-- Extract text from turn-role messages (user/tool) for request moderation.
-- `roles` is a set such as {user = true, tool = true} selecting which roles to
-- collect. mode "last" (default): only the last consecutive block of messages
-- whose role is in `roles` -- the latest turn, i.e. a fresh user message or the
-- tool results appended in the current agent round, so history is not re-checked.
-- mode "all": every such message. The system role is handled separately by
-- extract_system_content because it is not subject to the last-turn rule.
function _M.extract_turn_content(body, mode, roles)
    local contents = {}
    if type(body.messages) ~= "table" then
        return contents
    end
    local messages = body.messages
    local start_idx = 1
    if mode ~= "all" then
        start_idx = nil
        for i = #messages, 1, -1 do
            if is_turn_role(messages[i], roles) then
                start_idx = i
            else
                break
            end
        end
        if not start_idx then
            return contents
        end
    end
    for i = start_idx, #messages do
        if is_turn_role(messages[i], roles) then
            append_message_text(contents, messages[i])
        end
    end
    return contents
end


-- Extract system-role text for request moderation. Unlike turn content, the
-- system prompt is checked on every request (it can be poisoned by malicious
-- ToolCall arguments), so the last-turn rule does not apply here.
function _M.extract_system_content(body)
    local contents = {}
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            if type(message) == "table" and message.role == "system" then
                append_message_text(contents, message)
            end
        end
    end
    return contents
end


--- Get messages in canonical {role, content} format.
-- OpenAI Chat content may be a plain string or an array of typed parts
-- (e.g. {type = "text", text = "..."}); the text parts are flattened so
-- consumers always receive string content, consistent with the other adapters.
function _M.get_messages(body)
    local messages = {}
    if type(body.messages) == "table" then
        for _, message in ipairs(body.messages) do
            local texts = {}
            append_message_text(texts, message)
            if #texts > 0 then
                core.table.insert(messages, {
                    role = message.role,
                    content = table.concat(texts, " "),
                })
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
    for i = 1, #msgs do
        new_messages[i] = msgs[i]
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
        core.table.insert(body.messages, msg)
    end
end


--- Get raw request content for logging.
function _M.get_request_content(body)
    return body.messages
end


--- Build a deny response in OpenAI Chat format.
-- opts: {text, model, usage, stream}
function _M.build_deny_response(opts)
    if opts.stream then
        local data = {
            id = uuid.generate_v4(),
            object = "chat.completion.chunk",
            model = opts.model,
            choices = {{
                index = 0,
                delta = { content = opts.text },
                finish_reason = "stop"
            }},
            usage = opts.usage,
        }
        return "data: " .. core.json.encode(data) .. "\n\n" .. "data: [DONE]"
    else
        return core.json.encode({
            id = uuid.generate_v4(),
            object = "chat.completion",
            model = opts.model,
            choices = {{
                index = 0,
                message = { role = "assistant", content = opts.text },
                finish_reason = "stop"
            }},
            usage = opts.usage,
        })
    end
end


--- Build an empty usage object with zero values.
function _M.empty_usage()
    return { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
end


--- Check if an SSE event is a data event (contains parseable content).
function _M.is_data_event(event)
    return event.type == "message" and event.data ~= "[DONE]"
end


--- Check if an SSE event is the terminal/done event.
function _M.is_done_event(event)
    return event.data == "[DONE]"
end


--- Build a terminal SSE event string.
function _M.build_done_event()
    return "data: [DONE]"
end


return _M
