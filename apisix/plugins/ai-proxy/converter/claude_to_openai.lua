local core = require("apisix.core")
local type = type
local sse = require("apisix.plugins.ai-drivers.sse")
local table = table
local ipairs = ipairs
local tostring = tostring

local _M = {}

-- Map OpenAI finish_reason to Claude stop_reason
local STOP_REASON_MAP = {
    stop = "end_turn",
    length = "max_tokens",
    tool_calls = "tool_use",
    content_filter = "end_turn",
}

local function map_stop_reason(finish_reason)
    if not finish_reason or finish_reason == core.json.null then
        return "end_turn"
    end
    return STOP_REASON_MAP[finish_reason] or "end_turn"
end

-- Deep-copy messages array to avoid mutating the original request table
local function deep_copy_messages(messages)
    local copy = core.table.new(#messages, 0)
    for i, msg in ipairs(messages) do
        copy[i] = core.table.clone(msg)
    end
    return copy
end

local function concat_text_blocks(blocks, context)
    if type(blocks) ~= "table" then
        return nil, "unsupported content type in " .. context .. ": expected table, got "
            .. type(blocks)
    end

    if blocks.type ~= nil then
        if blocks.type ~= "text" or type(blocks.text) ~= "string" then
            return nil, "unsupported content type in " .. context .. ": " .. tostring(blocks.type)
        end
        return blocks.text
    end

    local result = {}
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" or block.type ~= "text" or type(block.text) ~= "string" then
            local block_type = type(block) == "table" and tostring(block.type) or type(block)
            return nil, "unsupported content type in " .. context .. ": " .. block_type
        end
        core.table.insert(result, block.text)
    end

    return table.concat(result, "")
end

local function normalize_stop_sequences(stop_sequences)
    if type(stop_sequences) == "string" then
        return stop_sequences
    end

    if type(stop_sequences) == "table" then
        local stops = {}
        for _, item in ipairs(stop_sequences) do
            if type(item) ~= "string" then
                return nil, "request format doesn't match: stop_sequences must be string array"
            end
            core.table.insert(stops, item)
        end
        return stops
    end

    return nil, "request format doesn't match: stop_sequences must be string or array"
end

function _M.convert_request(request_table)
    local openai_req = core.table.clone(request_table)
    openai_req.messages = deep_copy_messages(request_table.messages)

    if type(openai_req.messages) ~= "table" or #openai_req.messages == 0 then
        return nil, "request format doesn't match: messages is required"
    end

    if openai_req.system then
        local system_content
        if type(openai_req.system) == "string" then
            system_content = openai_req.system
        else
            local err
            system_content, err = concat_text_blocks(openai_req.system, "system")
            if err then
                return nil, err
            end
        end

        if system_content and system_content ~= "" then
            core.table.insert(openai_req.messages, 1, {
                role = "system",
                content = system_content
            })
        end
        openai_req.system = nil
    end

    for _, message in ipairs(openai_req.messages) do
        if type(message) == "table" and message.content ~= nil then
            if type(message.content) == "table" then
                local merged, err = concat_text_blocks(message.content, "messages")
                if err then
                    return nil, err
                end
                message.content = merged
            elseif type(message.content) ~= "string" then
                return nil, "unsupported content type in messages"
            end
        end
    end

    if openai_req.stop_sequences ~= nil then
        local stop, err = normalize_stop_sequences(openai_req.stop_sequences)
        if err then
            return nil, err
        end
        openai_req.stop = stop
        openai_req.stop_sequences = nil
    end

    if openai_req.temperature ~= nil and type(openai_req.temperature) ~= "number" then
        return nil, "request format doesn't match: temperature must be number"
    end

    if openai_req.top_p ~= nil and type(openai_req.top_p) ~= "number" then
        return nil, "request format doesn't match: top_p must be number"
    end

    return openai_req
end

function _M.convert_response(openai_res)
    local content = ""
    local finish_reason = "end_turn"

    if openai_res.choices and openai_res.choices[1] then
        if openai_res.choices[1].message then
            content = openai_res.choices[1].message.content or ""
        end
        finish_reason = map_stop_reason(openai_res.choices[1].finish_reason)
    end

    local input_tokens = 0
    local output_tokens = 0
    if openai_res.usage then
        input_tokens = openai_res.usage.prompt_tokens or 0
        output_tokens = openai_res.usage.completion_tokens or 0
    end

    return {
        id = openai_res.id or "msg_unknown",
        type = "message",
        role = "assistant",
        model = openai_res.model or "unknown",
        content = {
            {
                type = "text",
                text = content
            }
        },
        stop_reason = finish_reason,
        stop_sequence = core.json.null,
        usage = {
            input_tokens = input_tokens,
            output_tokens = output_tokens
        }
    }
end

local OPENAI_TO_CLAUDE_ERROR_TYPE = {
    ["401"] = "authentication_error",
    ["403"] = "permission_error",
    ["404"] = "not_found_error",
    ["429"] = "rate_limit_error",
    ["500"] = "api_error",
}

function _M.convert_error_response(status, openai_body)
    local message = "unknown error"
    if type(openai_body) == "table" and type(openai_body.error) == "table" then
        message = openai_body.error.message or message
    elseif type(openai_body) == "table" and openai_body.error then
        message = tostring(openai_body.error)
    end

    local error_type = OPENAI_TO_CLAUDE_ERROR_TYPE[tostring(status)] or "api_error"

    return {
        type = "error",
        error = {
            type = error_type,
            message = message,
        }
    }
end

local function get_claude_state(ctx)
    if not ctx.claude_state then
        ctx.claude_state = {
            sse_started = false,
            content_block_stopped = false,
            message_delta_emitted = false,
            stop_reason = nil,
            pending_output_tokens = 0,
            sse_buffer = "",
        }
    end
    return ctx.claude_state
end

function _M.convert_sse_events(ctx, chunk)
    local state = get_claude_state(ctx)

    local buffered = state.sse_buffer .. chunk
    if not core.string.has_suffix(buffered, "\n\n") then
        state.sse_buffer = buffered
        return nil
    end
    state.sse_buffer = ""

    local events = sse.decode(buffered)
    if not events or #events == 0 then
        core.log.warn("SSE decode returned no events for buffered chunk")
        return "event: error\ndata: " .. core.json.encode({
            type = "error",
            error = {
                type = "api_error",
                message = "failed to decode SSE events",
            }
        }) .. "\n\n"
    end

    local out_events = {}

    local function emit_message_start(data)
        if state.sse_started then
            return
        end
        state.sse_started = true
        core.table.insert(out_events, "event: message_start\ndata: " .. core.json.encode({
            type = "message_start",
            message = {
                id = data and data.id or "msg_unknown",
                type = "message",
                role = "assistant",
                model = data and data.model or "unknown",
                content = {},
                stop_reason = core.json.null,
                stop_sequence = core.json.null,
                usage = { input_tokens = 0, output_tokens = 0 }
            }
        }) .. "\n\n")

        core.table.insert(out_events, "event: content_block_start\ndata: " .. core.json.encode({
            type = "content_block_start",
            index = 0,
            content_block = { type = "text", text = "" }
        }) .. "\n\n")
    end

    local function emit_content_block_stop()
        if state.content_block_stopped then
            return
        end
        state.content_block_stopped = true
        core.table.insert(out_events, "event: content_block_stop\ndata: " .. core.json.encode({
            type = "content_block_stop",
            index = 0
        }) .. "\n\n")
    end

    local function emit_message_delta(output_tokens)
        if state.message_delta_emitted then
            return
        end
        state.message_delta_emitted = true
        core.table.insert(out_events, "event: message_delta\ndata: " .. core.json.encode({
            type = "message_delta",
            delta = {
                stop_reason = state.stop_reason or "end_turn",
                stop_sequence = core.json.null
            },
            usage = {
                output_tokens = output_tokens or 0
            }
        }) .. "\n\n")
    end

    for _, event in ipairs(events) do
        if event.type == "message" and event.data ~= "[DONE]" then
            local data, err = core.json.decode(event.data)
            if not data then
                core.log.warn("failed to decode SSE data: ", err)
                core.table.insert(out_events, "event: error\ndata: " .. core.json.encode({
                    type = "error",
                    error = {
                        type = "api_error",
                        message = "failed to decode upstream SSE event",
                    }
                }) .. "\n\n")
                goto CONTINUE
            end

            emit_message_start(data)

            if data.choices and data.choices[1] then
                local choice = data.choices[1]
                if choice.delta and choice.delta.content and choice.delta.content ~= "" then
                    core.table.insert(out_events, "event: content_block_delta\ndata: " .. core.json.encode({
                        type = "content_block_delta",
                        index = 0,
                        delta = { type = "text_delta", text = choice.delta.content }
                    }) .. "\n\n")
                end

                if choice.finish_reason and choice.finish_reason ~= core.json.null then
                    state.stop_reason = map_stop_reason(choice.finish_reason)
                    emit_content_block_stop()
                end
            end

            if data.usage and type(data.usage) == "table" then
                state.pending_output_tokens = data.usage.completion_tokens or 0
            end
        elseif event.type == "done" then
            emit_message_start(nil)
            if not state.content_block_stopped then
                state.stop_reason = state.stop_reason or "end_turn"
                emit_content_block_stop()
            end
            emit_message_delta(state.pending_output_tokens or 0)
            core.table.insert(out_events, "event: message_stop\ndata: " .. core.json.encode({
                type = "message_stop"
            }) .. "\n\n")
        end

        ::CONTINUE::
    end

    if #out_events > 0 then
        return table.concat(out_events, "")
    end

    return nil
end

return _M
