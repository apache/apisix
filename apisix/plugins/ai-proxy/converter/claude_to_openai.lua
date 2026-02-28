local core = require("apisix.core")
local type = type
local sse = require("apisix.plugins.ai-drivers.sse")
local table = table
local ipairs = ipairs

local _M = {}

function _M.convert_request(request_table)
    local openai_req = core.table.clone(request_table)
    
    if openai_req.system then
        local system_content
        if type(openai_req.system) == "string" then
            system_content = openai_req.system
        elseif type(openai_req.system) == "table" then
            system_content = ""
            for _, block in ipairs(openai_req.system) do
                if type(block) == "table" and block.type == "text" then
                    system_content = system_content .. block.text
                end
            end
        end
        
        if system_content and system_content ~= "" then
            if not openai_req.messages then
                openai_req.messages = {}
            end
            core.table.insert(openai_req.messages, 1, {
                role = "system",
                content = system_content
            })
        end
        openai_req.system = nil
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
        if openai_res.choices[1].finish_reason ~= "stop" and openai_res.choices[1].finish_reason ~= nil then
            finish_reason = openai_res.choices[1].finish_reason
        end
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

function _M.convert_sse_events(ctx, chunk)
    local events = sse.decode(chunk)
    if not events or #events == 0 then
        return chunk
    end
    
    local out_events = {}
    
    for _, event in ipairs(events) do
        if event.type == "message" and event.data ~= "[DONE]" then
            local data, err = core.json.decode(event.data)
            if data then
                if not ctx.claude_sse_started then
                    ctx.claude_sse_started = true
                    core.table.insert(out_events, "event: message_start\ndata: " .. core.json.encode({
                        type = "message_start",
                        message = {
                            id = data.id or "msg_unknown",
                            type = "message",
                            role = "assistant",
                            model = data.model or "unknown",
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
                        local stop_reason = choice.finish_reason == "stop" and "end_turn" or choice.finish_reason
                        ctx.claude_stop_reason = stop_reason
                        
                        core.table.insert(out_events, "event: content_block_stop\ndata: " .. core.json.encode({
                            type = "content_block_stop",
                            index = 0
                        }) .. "\n\n")
                    end
                end
                
                if data.usage and type(data.usage) == "table" then
                    core.table.insert(out_events, "event: message_delta\ndata: " .. core.json.encode({
                        type = "message_delta",
                        delta = {
                            stop_reason = ctx.claude_stop_reason or "end_turn",
                            stop_sequence = core.json.null
                        },
                        usage = {
                            output_tokens = data.usage.completion_tokens or 0
                        }
                    }) .. "\n\n")
                    
                    ctx.claude_message_delta_emitted = true
                end
            end
        elseif event.type == "message" and event.data == "[DONE]" then
            if not ctx.claude_message_delta_emitted and ctx.claude_stop_reason then
                core.table.insert(out_events, "event: message_delta\ndata: " .. core.json.encode({
                    type = "message_delta",
                    delta = {
                        stop_reason = ctx.claude_stop_reason,
                        stop_sequence = core.json.null
                    },
                    usage = { output_tokens = 0 }
                }) .. "\n\n")
            end
            
            core.table.insert(out_events, "event: message_stop\ndata: " .. core.json.encode({
                type = "message_stop"
            }) .. "\n\n")
        end
    end
    
    if #out_events > 0 then
        return table.concat(out_events, "")
    else
        return ""
    end
end

return _M
