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

--- Converter: Anthropic Messages → OpenAI Chat Completions.
-- Converts client requests from Anthropic Messages API format to
-- OpenAI Chat Completions format, and converts provider responses
-- back from OpenAI to Anthropic format.
--
-- Converters work DOWNSTREAM of adapters: the target adapter (openai-chat)
-- parses the provider's response, and this converter transforms the parsed
-- result into the client's format (Anthropic Messages).

local core = require("apisix.core")
local table = table
local type = type
local ipairs = ipairs
local tostring = tostring
local setmetatable = setmetatable

local _M = {
    from = "anthropic-messages",
    to = "openai-chat",
}


-- SSE event helpers
local function make_sse_event(event_type, data)
    return { type = event_type, data = core.json.encode(data) }
end

local function push_content_block_stop(events, idx)
    table.insert(events, make_sse_event("content_block_stop", {
        type = "content_block_stop",
        index = idx,
    }))
end

local function push_content_block_start(events, idx, block)
    table.insert(events, make_sse_event("content_block_start", {
        type  = "content_block_start",
        index = idx,
        content_block = block,
    }))
end

local function push_content_block_delta(events, idx, delta)
    table.insert(events, make_sse_event("content_block_delta", {
        type  = "content_block_delta",
        index = idx,
        delta = delta,
    }))
end

local openai_stop_reason_map = {
    stop = "end_turn",
    length = "max_tokens",
    content_filter = "end_turn",
    tool_calls = "tool_use",
}


--- Convert an incoming Anthropic request to OpenAI Chat format.
function _M.convert_request(request_table, ctx)
    if type(request_table) ~= "table" then
        return nil, "request body must be a table"
    end

    if type(request_table.messages) ~= "table" or
       #request_table.messages == 0 then
        return nil, "missing messages"
    end

    local openai_body = core.table.clone(request_table)

    -- 1. Handle System Prompt
    local messages = {}
    if request_table.system then
        local system_content = ""
        if type(request_table.system) == "string" then
            system_content = request_table.system
        elseif type(request_table.system) == "table" then
            for _, block in ipairs(request_table.system) do
                if type(block) == "table" and block.type == "text"
                        and type(block.text) == "string" then
                    system_content = system_content .. block.text
                end
            end
        end

        if system_content ~= "" then
            table.insert(messages, {
                role = "system",
                content = system_content
            })
        end
        openai_body.system = nil
    end

    -- 2. Convert Messages (including tool calls and results)
    for i, msg in ipairs(request_table.messages) do
        if type(msg) ~= "table" or type(msg.role) ~= "string" then
            return nil, "invalid message at index " .. i
        end
        if type(msg.content) ~= "string" and type(msg.content) ~= "table" then
            return nil, "invalid message content at index " .. i
        end

        local new_msg = {
            role = msg.role,
            content = ""
        }
        if type(msg.content) == "string" then
            new_msg.content = msg.content
        elseif type(msg.content) == "table" then
            local tool_calls = {}
            local tool_results = {}

            for _, block in ipairs(msg.content) do
                if type(block) ~= "table" then
                    core.log.warn("unexpected non-table content block in Anthropic ",
                                  "request, skipping: ", tostring(block))
                    goto CONTINUE_BLOCK
                end

                if block.type == "text" and type(block.text) == "string" then
                    new_msg.content = (new_msg.content or "") .. block.text
                elseif block.type == "tool_use" then
                    if type(block.id) == "string" and type(block.name) == "string" then
                        table.insert(tool_calls, {
                            id = block.id,
                            type = "function",
                            ["function"] = {
                                name = block.name,
                                arguments = core.json.encode(block.input or {})
                            }
                        })
                    end
                elseif block.type == "tool_result" then
                    if type(block.tool_use_id) == "string" then
                        table.insert(tool_results, {
                            role = "tool",
                            tool_call_id = block.tool_use_id,
                            content = type(block.content) == "table"
                                      and core.json.encode(block.content)
                                      or tostring(block.content or "")
                        })
                    end
                end

                ::CONTINUE_BLOCK::
            end

            if #tool_calls > 0 then
                new_msg.tool_calls = tool_calls
                new_msg.content = new_msg.content ~= "" and new_msg.content or nil
            end

            if #tool_results > 0 then
                if new_msg.content and new_msg.content ~= "" then
                    table.insert(messages, { role = msg.role, content = new_msg.content })
                end
                for _, tr in ipairs(tool_results) do
                    table.insert(messages, tr)
                end
                goto CONTINUE
            end
        end

        table.insert(messages, new_msg)
        ::CONTINUE::
    end
    openai_body.messages = messages

    -- 3. Convert Tools Definition
    if type(request_table.tools) == "table" then
        local openai_tools = {}
        for i, tool in ipairs(request_table.tools) do
            if type(tool) ~= "table" or type(tool.name) ~= "string" or tool.name == "" then
                return nil, "invalid tool definition at index " .. i
            end
            table.insert(openai_tools, {
                type = "function",
                ["function"] = {
                    name = tool.name,
                    description = tool.description,
                    parameters = tool.input_schema
                }
            })
        end
        openai_body.tools = openai_tools
    end

    -- 4. Map Parameters
    if openai_body.max_tokens then
        openai_body.max_completion_tokens = openai_body.max_tokens
    end

    if openai_body.stop_sequences then
        openai_body.stop = openai_body.stop_sequences
        openai_body.stop_sequences = nil
    end

    return openai_body
end


--- Convert an OpenAI response back to Anthropic format.
function _M.convert_response(res_body, ctx)
    if type(res_body) ~= "table" then
        return nil, "response body must be a table"
    end

    local choice = res_body.choices and res_body.choices[1]
    if not choice then
        return nil, "no choices in response"
    end

    local model = ctx.var.llm_model

    local content = {}
    local text = type(choice.message) == "table" and choice.message.content
    if type(text) == "string" and text ~= "" then
        table.insert(content, { type = "text", text = text })
    end

    if type(choice.message) == "table" and type(choice.message.tool_calls) == "table" then
        for _, tc in ipairs(choice.message.tool_calls) do
            local input = {}
            if type(tc["function"]) == "table" and type(tc["function"].arguments) == "string" then
                local decoded, err = core.json.decode(tc["function"].arguments)
                if decoded == nil then
                    return nil, "invalid tool_call arguments: " .. (err or "decode error")
                end
                input = decoded
            end
            table.insert(content, {
                type = "tool_use",
                id = tc.id or "",
                name = (type(tc["function"]) == "table" and tc["function"].name) or "",
                input = input
            })
        end
    end

    if #content == 0 then
        content = {{ type = "text", text = "" }}
    end

    local anthropic_res = {
        id = res_body.id,
        type = "message",
        role = "assistant",
        model = model or res_body.model,
        content = content,
        stop_reason = openai_stop_reason_map[choice.finish_reason] or "end_turn",
        usage = {
            input_tokens = type(res_body.usage) == "table" and res_body.usage.prompt_tokens or 0,
            output_tokens = type(res_body.usage) == "table" and res_body.usage.completion_tokens or 0,
        }
    }

    if type(res_body.usage) == "table"
            and type(res_body.usage.prompt_tokens_details) == "table" then
        anthropic_res.usage.cache_read_input_tokens =
            res_body.usage.prompt_tokens_details.cached_tokens or 0
    end

    return anthropic_res
end


--- Convert an OpenAI SSE chunk to Anthropic SSE events.
-- state: table to maintain stream state (is_first, content_index, etc.)
local function openai_to_anthropic_sse(openai_chunk, state)
    if type(openai_chunk) ~= "table" then
        return {}
    end
    if type(state) ~= "table" then
        return {}
    end
    local events = {}
    local choice = openai_chunk.choices and openai_chunk.choices[1]

    -- If finish_reason was seen, we deferred message_delta+message_stop to allow
    -- a trailing usage-only chunk to be merged in. Flush now.
    if state.is_done then
        if state.pending_stop then
            local message_delta = state.pending_message_delta
            if type(openai_chunk.usage) == "table" and not message_delta.usage then
                message_delta.usage = {
                    input_tokens  = openai_chunk.usage.prompt_tokens or 0,
                    output_tokens = openai_chunk.usage.completion_tokens or 0,
                }
            end
            table.insert(events, make_sse_event("message_delta", message_delta))
            table.insert(events, make_sse_event("message_stop", { type = "message_stop" }))
            state.pending_stop = false
            state.pending_message_delta = nil
        end
        return events
    end

    -- 1. Initialize message on first chunk
    if state.is_first then
        local message = {
            id = openai_chunk.id,
            type = "message",
            role = "assistant",
            model = openai_chunk.model,
            content = {},
            usage = { input_tokens = 0, output_tokens = 0 }
        }
        setmetatable(message.content, core.json.empty_array_mt)

        table.insert(events, make_sse_event("message_start", {
            type = "message_start",
            message = message,
        }))
        push_content_block_start(events, 0, { type = "text", text = "" })

        state.is_first = false
        state.content_index = 0
        state.current_open_block = 0
        state.tool_call_indices = {}
    end

    -- 2. Handle text content delta
    if choice and choice.delta and type(choice.delta.content) == "string"
            and choice.delta.content ~= "" then
        push_content_block_delta(events, 0, {
            type = "text_delta",
            text = choice.delta.content,
        })
    end

    -- 3. Handle tool_calls deltas
    if choice and choice.delta and type(choice.delta.tool_calls) == "table" then
        for _, tc_delta in ipairs(choice.delta.tool_calls) do
            if type(tc_delta) ~= "table" then
                goto continue_tc
            end
            local tc_idx = tc_delta.index
            if tc_idx == nil then
                goto continue_tc
            end

            if not state.tool_call_indices[tc_idx] then
                if state.current_open_block ~= nil then
                    push_content_block_stop(events, state.current_open_block)
                end
                state.content_index = state.content_index + 1
                state.tool_call_indices[tc_idx] = state.content_index
                state.current_open_block = state.content_index

                local fn = tc_delta["function"] or {}
                push_content_block_start(events, state.content_index, {
                    type  = "tool_use",
                    id    = tc_delta.id or "",
                    name  = fn.name or "",
                    input = {},
                })
            end

            local fn = tc_delta["function"]
            local args = fn and fn.arguments
            if type(args) == "string" and args ~= "" then
                push_content_block_delta(events, state.tool_call_indices[tc_idx], {
                    type         = "input_json_delta",
                    partial_json = args,
                })
            end

            ::continue_tc::
        end
    end

    -- 4. Handle stream completion
    if choice and type(choice.finish_reason) == "string" then
        if state.current_open_block ~= nil then
            push_content_block_stop(events, state.current_open_block)
            state.current_open_block = nil
        end

        local message_delta = {
            type = "message_delta",
            delta = {
                stop_reason = openai_stop_reason_map[choice.finish_reason] or "end_turn",
            },
        }

        if type(openai_chunk.usage) == "table" then
            message_delta.usage = {
                input_tokens  = openai_chunk.usage.prompt_tokens or 0,
                output_tokens = openai_chunk.usage.completion_tokens or 0,
            }
        end

        state.pending_message_delta = message_delta
        state.pending_stop = true
        state.is_done = true
    end

    return events
end


--- Convert parsed SSE events (from openai-chat adapter) to Anthropic format.
-- Called with the result of openai_chat_adapter.parse_sse_event().
-- @param parsed table Parsed SSE event from target adapter
-- @param ctx table Request context
-- @param state table Mutable converter state
-- @return table|nil List of Anthropic SSE events to send to client
function _M.convert_sse_events(parsed, _, state)
    if not parsed or parsed.type == "skip" then
        return nil
    end

    if parsed.type == "done" then
        -- Flush any deferred message_stop
        if state.pending_stop then
            return openai_to_anthropic_sse({ choices = {} }, state)
        end
        return nil
    end

    if parsed.data then
        return openai_to_anthropic_sse(parsed.data, state)
    end

    return nil
end


return _M
