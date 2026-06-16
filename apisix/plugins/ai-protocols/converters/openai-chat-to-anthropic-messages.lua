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

--- Converter: OpenAI Chat Completions → Anthropic Messages.
-- Converts client requests from OpenAI Chat Completions format to the native
-- Anthropic Messages API format, and converts provider responses back from
-- Anthropic to OpenAI format. The inverse of
-- ai-protocols/converters/anthropic-messages-to-openai-chat.lua.
--
-- Uses whitelist body construction: the outgoing Anthropic body is built from
-- scratch with only explicitly converted fields. Unknown OpenAI fields never
-- reach the upstream provider.
--
-- Streaming (stream=true) is not yet supported in this direction and is
-- rejected in convert_request; see the tracking issue.

local core = require("apisix.core")
local table = table
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring

-- Anthropic Messages requires max_tokens; OpenAI Chat makes it optional, so
-- supply a default when the client omits it. Route override.llm_options.max_tokens
-- still force-overrides this afterward via the provider capability rewrite.
local DEFAULT_MAX_TOKENS = 4096

local _M = {
    from = "openai-chat",
    to = "anthropic-messages",
}


local anthropic_stop_reason_map = {
    end_turn = "stop",
    stop_sequence = "stop",
    max_tokens = "length",
    tool_use = "tool_calls",
    pause_turn = "stop",
    refusal = "stop",
}


-- Convert OpenAI reasoning_effort to an Anthropic thinking config.
-- Mirrors the budget thresholds used by the reverse converter.
local function convert_reasoning_effort(effort)
    if effort == "low" then
        return { type = "enabled", budget_tokens = 1024 }
    elseif effort == "medium" then
        return { type = "enabled", budget_tokens = 8192 }
    elseif effort == "high" then
        return { type = "enabled", budget_tokens = 24576 }
    end
    return nil
end


-- Convert OpenAI tool_choice to Anthropic format.
local function convert_tool_choice(tc)
    if tc == "auto" then
        return { type = "auto" }
    elseif tc == "required" then
        return { type = "any" }
    elseif tc == "none" then
        return { type = "none" }
    elseif type(tc) == "table" and tc.type == "function"
            and type(tc["function"]) == "table"
            and type(tc["function"].name) == "string" then
        return { type = "tool", name = tc["function"].name }
    end
    return nil
end


-- Convert an OpenAI image_url content part to an Anthropic image block.
-- Handles both base64 data URLs and remote URLs.
local function convert_image_part(part)
    local image_url = part.image_url
    local url
    if type(image_url) == "table" then
        url = image_url.url
    elseif type(image_url) == "string" then
        url = image_url
    end
    if type(url) ~= "string" or url == "" then
        return nil
    end

    -- data:<media_type>;base64,<data>
    local media_type, data = url:match("^data:([^;]+);base64,(.+)$")
    if media_type and data then
        return {
            type = "image",
            source = {
                type = "base64",
                media_type = media_type,
                data = data,
            },
        }
    end

    return {
        type = "image",
        source = {
            type = "url",
            url = url,
        },
    }
end


-- Convert an OpenAI message content (string or content-part array) to a plain
-- string or an array of Anthropic content blocks. Returns a string when the
-- content is purely text, otherwise an array of blocks.
local function convert_content(content)
    if type(content) == "string" then
        return content
    end
    if type(content) ~= "table" then
        return ""
    end

    local blocks = {}
    local has_non_text = false
    for _, part in ipairs(content) do
        if type(part) == "table" then
            if part.type == "text" and type(part.text) == "string" then
                table.insert(blocks, { type = "text", text = part.text })
            elseif part.type == "image_url" then
                local img = convert_image_part(part)
                if img then
                    table.insert(blocks, img)
                    has_non_text = true
                end
            else
                core.log.warn("dropping unsupported OpenAI content part type '",
                              tostring(part.type), "' in openai-chat to ",
                              "anthropic-messages conversion")
            end
        end
    end

    -- Flatten a single text block back to a plain string.
    if not has_non_text and #blocks == 1 and blocks[1].type == "text" then
        return blocks[1].text
    end
    if #blocks == 0 then
        return ""
    end
    return blocks
end


-- Append a tool_result block to the trailing user message, coalescing
-- consecutive OpenAI `tool` messages into a single Anthropic user message
-- (Anthropic carries tool results as user-role tool_result blocks).
local function append_tool_result(messages, tool_call_id, content)
    local block = {
        type = "tool_result",
        tool_use_id = tool_call_id,
        content = type(content) == "string" and content or "",
    }
    local last = messages[#messages]
    if last and last.role == "user" and type(last.content) == "table"
            and last._tool_result_group then
        table.insert(last.content, block)
    else
        table.insert(messages, {
            role = "user",
            content = { block },
            _tool_result_group = true,
        })
    end
end


--- Convert an incoming OpenAI Chat request to Anthropic Messages format.
function _M.convert_request(request_table, ctx)
    if type(request_table) ~= "table" then
        return nil, "request body must be a table"
    end

    if request_table.stream == true then
        return nil, "streaming is not yet supported for openai-chat to "
            .. "anthropic-messages conversion"
    end

    if type(request_table.messages) ~= "table" or
       #request_table.messages == 0 then
        return nil, "missing messages"
    end

    -- Whitelist body construction: only explicitly converted fields are set.
    local anthropic_body = {}

    -- Model passthrough
    if type(request_table.model) == "string" then
        anthropic_body.model = request_table.model
    end

    -- max_tokens (required by Anthropic). Accept either OpenAI field.
    anthropic_body.max_tokens = request_table.max_tokens
        or request_table.max_completion_tokens
        or DEFAULT_MAX_TOKENS

    -- Simple parameter passthrough
    if request_table.temperature then
        anthropic_body.temperature = request_table.temperature
    end
    if request_table.top_p then
        anthropic_body.top_p = request_table.top_p
    end

    -- stop → stop_sequences (string or array)
    if type(request_table.stop) == "string" then
        anthropic_body.stop_sequences = { request_table.stop }
    elseif type(request_table.stop) == "table" then
        anthropic_body.stop_sequences = request_table.stop
    end

    -- reasoning_effort → thinking
    if type(request_table.reasoning_effort) == "string" then
        local thinking = convert_reasoning_effort(request_table.reasoning_effort)
        if thinking then
            anthropic_body.thinking = thinking
        end
    end

    -- user / safety_identifier → metadata.user_id
    local user_id = request_table.safety_identifier or request_table.user
    if type(user_id) == "string" then
        anthropic_body.metadata = { user_id = user_id }
    end

    -- tool_choice conversion
    if request_table.tool_choice ~= nil then
        local tc = convert_tool_choice(request_table.tool_choice)
        if tc then
            if tc.type == "tool" or tc.type == "any" or tc.type == "auto" then
                if request_table.parallel_tool_calls == false then
                    tc.disable_parallel_tool_use = true
                end
            end
            anthropic_body.tool_choice = tc
        end
    end

    -- tools conversion (OpenAI function tools → Anthropic tools)
    if type(request_table.tools) == "table" and #request_table.tools > 0 then
        local anthropic_tools = {}
        for _, tool in ipairs(request_table.tools) do
            if type(tool) == "table" and tool.type == "function"
                    and type(tool["function"]) == "table"
                    and type(tool["function"].name) == "string" then
                local fn = tool["function"]
                table.insert(anthropic_tools, {
                    name = fn.name,
                    description = fn.description,
                    input_schema = fn.parameters or { type = "object" },
                })
            end
        end
        if #anthropic_tools > 0 then
            anthropic_body.tools = anthropic_tools
        end
    end

    -- Messages: split system role out to top-level `system`, convert the rest.
    local system_parts = {}
    local messages = {}
    for i, msg in ipairs(request_table.messages) do
        if type(msg) ~= "table" or type(msg.role) ~= "string" then
            return nil, "invalid message at index " .. i
        end

        if msg.role == "system" or msg.role == "developer" then
            local text = msg.content
            if type(text) == "table" then
                -- Concatenate text parts of a structured system message.
                local parts = {}
                for _, part in ipairs(text) do
                    if type(part) == "table" and part.type == "text"
                            and type(part.text) == "string" then
                        table.insert(parts, part.text)
                    end
                end
                text = table.concat(parts, "")
            end
            if type(text) == "string" and text ~= "" then
                table.insert(system_parts, text)
            end
            goto CONTINUE
        end

        if msg.role == "tool" then
            if type(msg.tool_call_id) == "string" then
                append_tool_result(messages, msg.tool_call_id,
                                    convert_content(msg.content))
            end
            goto CONTINUE
        end

        -- user / assistant
        local new_msg = { role = msg.role }

        if msg.role == "assistant" and type(msg.tool_calls) == "table"
                and #msg.tool_calls > 0 then
            local blocks = {}
            -- Preserve any assistant text alongside the tool calls.
            local text = convert_content(msg.content)
            if type(text) == "string" and text ~= "" then
                table.insert(blocks, { type = "text", text = text })
            elseif type(text) == "table" then
                for _, b in ipairs(text) do
                    table.insert(blocks, b)
                end
            end
            for _, tc in ipairs(msg.tool_calls) do
                if type(tc) == "table" and tc.type == "function"
                        and type(tc["function"]) == "table" then
                    local input = {}
                    local args = tc["function"].arguments
                    if type(args) == "string" and args ~= "" then
                        local decoded, err = core.json.decode(args)
                        if decoded == nil then
                            return nil, "invalid tool_calls arguments at message "
                                .. i .. ": " .. (err or "decode error")
                        end
                        input = decoded
                    end
                    table.insert(blocks, {
                        type = "tool_use",
                        id = tc.id or "",
                        name = (tc["function"].name) or "",
                        input = input,
                    })
                end
            end
            new_msg.content = blocks
        else
            new_msg.content = convert_content(msg.content)
        end

        table.insert(messages, new_msg)
        ::CONTINUE::
    end

    -- Strip the internal grouping marker before emitting.
    for _, m in ipairs(messages) do
        m._tool_result_group = nil
    end

    anthropic_body.messages = messages

    if #system_parts > 0 then
        anthropic_body.system = table.concat(system_parts, "\n\n")
    end

    return anthropic_body
end


--- Convert an Anthropic Messages response back to OpenAI Chat format.
function _M.convert_response(res_body, ctx)
    if type(res_body) ~= "table" then
        return nil, "response body must be a table"
    end

    -- Error passthrough: convert upstream Anthropic errors to OpenAI error format
    if res_body.type == "error" or res_body.error then
        local err_obj = res_body.error
        local err_type = "api_error"
        local err_msg = ""
        if type(err_obj) == "table" then
            if type(err_obj.type) == "string" then
                err_type = err_obj.type
            end
            if type(err_obj.message) == "string" then
                err_msg = err_obj.message
            end
        elseif type(err_obj) == "string" then
            err_msg = err_obj
        end
        return {
            error = {
                message = err_msg,
                type = err_type,
                code = err_type,
            },
        }
    end

    local model = ctx.var.llm_model or res_body.model

    local text_parts = {}
    local reasoning_parts = {}
    local tool_calls = {}

    if type(res_body.content) == "table" then
        for _, block in ipairs(res_body.content) do
            if type(block) == "table" then
                if block.type == "text" and type(block.text) == "string" then
                    table.insert(text_parts, block.text)
                elseif block.type == "thinking" and type(block.thinking) == "string" then
                    table.insert(reasoning_parts, block.thinking)
                elseif block.type == "tool_use" then
                    table.insert(tool_calls, {
                        id = block.id or "",
                        type = "function",
                        ["function"] = {
                            name = block.name or "",
                            arguments = core.json.encode(block.input or {}),
                        },
                    })
                end
            end
        end
    end

    local message = { role = "assistant" }
    message.content = #text_parts > 0 and table.concat(text_parts, "") or core.json.null
    if #reasoning_parts > 0 then
        message.reasoning_content = table.concat(reasoning_parts, "")
    end
    if #tool_calls > 0 then
        message.tool_calls = tool_calls
    end

    local finish_reason = anthropic_stop_reason_map[res_body.stop_reason] or "stop"
    if #tool_calls > 0 and res_body.stop_reason == nil then
        finish_reason = "tool_calls"
    end

    -- Usage: Anthropic input/output tokens → OpenAI prompt/completion tokens.
    local usage = { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    if type(res_body.usage) == "table" then
        local u = res_body.usage
        local input_tokens = u.input_tokens or 0
        local cache_read = u.cache_read_input_tokens or 0
        local cache_creation = u.cache_creation_input_tokens or 0
        -- Anthropic input_tokens excludes cached tokens; OpenAI prompt_tokens
        -- is the total, so add cached tokens back in.
        local prompt_tokens = input_tokens + cache_read + cache_creation
        local completion_tokens = u.output_tokens or 0
        usage.prompt_tokens = prompt_tokens
        usage.completion_tokens = completion_tokens
        usage.total_tokens = prompt_tokens + completion_tokens
        if cache_read > 0 or cache_creation > 0 then
            usage.prompt_tokens_details = {
                cached_tokens = cache_read,
            }
        end
    end

    local openai_res = {
        id = res_body.id,
        object = "chat.completion",
        model = model,
        choices = {
            {
                index = 0,
                message = message,
                finish_reason = finish_reason,
            },
        },
        usage = usage,
    }

    return openai_res
end


--- Convert headers for the upstream request.
-- Transforms OpenAI-style auth/telemetry headers to Anthropic-compatible form.
function _M.convert_headers(headers)
    if type(headers) ~= "table" then
        return
    end

    -- Convert Authorization: Bearer <key> to x-api-key, unless the route's
    -- auth config already supplied an x-api-key.
    if not headers["x-api-key"] then
        local authz = headers["authorization"]
        if type(authz) == "string" then
            local key = authz:match("^[Bb]earer%s+(.+)$")
            if key and key ~= "" then
                headers["x-api-key"] = key
            end
        end
    end
    headers["authorization"] = nil

    -- Anthropic requires an API version header; supply a default if absent.
    if not headers["anthropic-version"] then
        headers["anthropic-version"] = "2023-06-01"
    end

    -- Remove OpenAI-specific and SDK telemetry headers.
    local to_remove = {}
    for k in pairs(headers) do
        if type(k) == "string" then
            if k:sub(1, 7) == "openai-" or k:sub(1, 12) == "x-stainless-" then
                table.insert(to_remove, k)
            end
        end
    end
    for _, k in ipairs(to_remove) do
        headers[k] = nil
    end
end


return _M
