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
-- Uses whitelist body construction: the outgoing OpenAI body is built
-- from scratch with only explicitly converted fields. Unknown Anthropic
-- fields never reach the upstream provider.

local core = require("apisix.core")
local resty_sha256 = require("resty.sha256")
local to_hex = require("resty.string").to_hex
local table = table
local type = type
local next = next
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local setmetatable = setmetatable
local ngx_re_gsub = ngx.re.gsub
local math_max = math.max
local string_sub = string.sub
local string_len = string.len

local _M = {
    from = "anthropic-messages",
    to = "openai-chat",
}


-- Anthropic built-in tool type prefixes (no input_schema, OpenAI can't handle them)
local BUILTIN_TOOL_PREFIXES = {
    "computer_", "bash_", "text_editor_", "web_search", "code_execution_"
}

-- OpenAI tool name constraints: max 64 chars, only [a-zA-Z0-9_-]
local TOOL_NAME_MAX_LEN = 64
local TOOL_NAME_HASH_LEN = 8
local TOOL_NAME_PREFIX_LEN = TOOL_NAME_MAX_LEN - TOOL_NAME_HASH_LEN - 1


-- Anthropic built-in tools have a type but no input_schema; OpenAI can't
-- handle them, so they never reach the upstream.
local function is_builtin_tool(tool)
    if type(tool.type) ~= "string" then
        return false
    end
    for _, prefix in ipairs(BUILTIN_TOOL_PREFIXES) do
        if string_sub(tool.type, 1, string_len(prefix)) == prefix then
            return true
        end
    end
    return false
end


local function tool_name_hash(name)
    local sha256 = resty_sha256:new()
    sha256:update(name)
    return string_sub(to_hex(sha256:final()), 1, TOOL_NAME_HASH_LEN)
end


-- Map an Anthropic tool name to the name used on the OpenAI side. Characters
-- outside [a-zA-Z0-9_-] become underscores, and any name that had to change is
-- rewritten as <55-char prefix>_<8 hex chars of sha256(original)>. Two rewritten
-- names therefore never collide, the same way LiteLLM's adapter avoids it.
-- (A tool named after another tool's hash still collides -- LiteLLM has the same
-- hole -- but nothing short of rewriting every name closes that.)
-- The mapping is a pure function of the name, which keeps the `tools` array and
-- the `tool_use` blocks in the conversation history in sync. `reverse` records
-- openai → original for the renamed tools, letting the response converter
-- restore the original name.
local function openai_tool_name(name, reverse)
    local sanitized = ngx_re_gsub(name, "[^a-zA-Z0-9_-]", "_", "jo")
    if sanitized == name and string_len(name) <= TOOL_NAME_MAX_LEN then
        return name
    end

    local renamed = string_sub(sanitized, 1, TOOL_NAME_PREFIX_LEN) .. "_"
                    .. tool_name_hash(name)
    reverse[renamed] = name
    return renamed
end


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
    function_call = "tool_use",
}


-- Convert an Anthropic image/document block to OpenAI image_url format.
local function convert_media_block(block)
    if block.type == "image" then
        local source = block.source
        if not source then
            return nil
        end
        if source.type == "base64" then
            if not source.data or source.data == "" then
                return nil
            end
            return {
                type = "image_url",
                image_url = {
                    url = "data:" .. (source.media_type or "image/png")
                          .. ";base64," .. source.data,
                },
            }
        elseif source.type == "url" and type(source.url) == "string"
                and source.url ~= "" then
            return {
                type = "image_url",
                image_url = { url = source.url },
            }
        end
    elseif block.type == "document" then
        local source = block.source
        if source and source.type == "base64" then
            if not source.data or source.data == "" then
                return nil
            end
            return {
                type = "image_url",
                image_url = {
                    url = "data:" .. (source.media_type or "application/pdf")
                          .. ";base64," .. source.data,
                },
            }
        end
    end
    return nil
end


local function concat_text_parts(parts)
    local text = ""
    for _, part in ipairs(parts) do
        if part.type == "text" then
            text = text .. (part.text or "")
        end
    end
    return text
end


-- JSON schema keywords holding a list of sub-schemas, and keywords holding a
-- map of named sub-schemas. Both have to be walked by normalize_strict_schema.
local SCHEMA_LIST_KEYWORDS = { "anyOf", "oneOf", "allOf" }
local SCHEMA_MAP_KEYWORDS = { "$defs", "definitions" }


-- Recursively make a JSON schema comply with OpenAI's strict mode, which
-- requires `additionalProperties: false` on every object and every property
-- listed in `required`. Mirrors LiteLLM's Anthropic adapter.
local function normalize_strict_schema(schema)
    if type(schema) ~= "table" then
        return
    end

    if schema.type == "object" and type(schema.properties) == "table" then
        schema.additionalProperties = false
        -- `required` must reach the upstream as a JSON array, including when the
        -- object declares no properties at all
        local required = setmetatable({}, core.json.array_mt)
        for name, prop in pairs(schema.properties) do
            table.insert(required, name)
            normalize_strict_schema(prop)
        end
        -- `properties` is a map, so the names come out unordered: sort them to
        -- keep the outgoing body stable
        table.sort(required)
        schema.required = required
    end

    normalize_strict_schema(schema.items)

    for _, key in ipairs(SCHEMA_LIST_KEYWORDS) do
        if type(schema[key]) == "table" then
            for _, sub in ipairs(schema[key]) do
                normalize_strict_schema(sub)
            end
        end
    end

    for _, key in ipairs(SCHEMA_MAP_KEYWORDS) do
        if type(schema[key]) == "table" then
            for _, def in pairs(schema[key]) do
                normalize_strict_schema(def)
            end
        end
    end
end


-- Convert Anthropic tool_choice to OpenAI format.
local function convert_tool_choice(tc)
    if type(tc) ~= "table" then
        return nil
    end
    local t = tc.type
    if t == "auto" then
        return "auto"
    elseif t == "any" then
        return "required"
    elseif t == "none" then
        return "none"
    elseif t == "tool" and type(tc.name) == "string" then
        return {
            type = "function",
            ["function"] = { name = tc.name },
        }
    end
    return nil
end


-- With adaptive thinking the depth comes from output_config.effort. When that
-- is absent we fall back to "medium", the same default LiteLLM's Anthropic
-- adapter uses.
local ADAPTIVE_DEFAULT_EFFORT = "medium"

-- thinking.budget_tokens buckets, matching LiteLLM's shared thresholds
local EFFORT_LOW_BUDGET = 1024
local EFFORT_MEDIUM_BUDGET = 2048
local EFFORT_HIGH_BUDGET = 4096


-- Convert Anthropic thinking config to OpenAI reasoning_effort.
-- `thinking.type` is one of "enabled", "disabled" or "adaptive". With
-- "adaptive" the depth is driven by output_config.effort instead of
-- budget_tokens, and the level is forwarded verbatim: Chat Completions takes
-- the same labels (none/minimal/low/medium/high/xhigh).
local function convert_thinking_config(thinking, output_config)
    if type(thinking) ~= "table" then
        return nil
    end

    if thinking.type == "adaptive" then
        if type(output_config) == "table" and type(output_config.effort) == "string"
                and output_config.effort ~= "" then
            return output_config.effort
        end
        return ADAPTIVE_DEFAULT_EFFORT
    end

    if thinking.type ~= "enabled" then
        return nil
    end
    local budget = thinking.budget_tokens
    if type(budget) ~= "number" then
        budget = 0
    end
    if budget >= EFFORT_HIGH_BUDGET then
        return "high"
    elseif budget >= EFFORT_MEDIUM_BUDGET then
        return "medium"
    elseif budget >= EFFORT_LOW_BUDGET then
        return "low"
    else
        return "minimal"
    end
end


-- Strip cch= entries from billing header text.
local function strip_cch_from_billing(text)
    if type(text) ~= "string" then
        return text
    end
    local prefix = "x-anthropic-billing-header:"
    if text:sub(1, #prefix):lower() ~= prefix then
        return text
    end
    local value = text:sub(#prefix + 1)
    -- Remove cch=<value> entries (with optional surrounding semicolons/spaces)
    value = ngx_re_gsub(value, [[ ?cch=[^;]*;?]], "", "jo")
    -- Clean up trailing/leading semicolons and spaces
    value = ngx_re_gsub(value, [[^[; ]+|[; ]+$]], "", "jo")
    if value == "" then
        return nil
    end
    return prefix .. value
end


-- Convert system prompt to OpenAI messages.
-- Always concatenates text blocks into a single string (cache_control is stripped).
local function convert_system(system)
    if type(system) == "string" then
        if system == "" then
            return nil
        end
        return { role = "system", content = system }
    end

    if type(system) ~= "table" then
        return nil
    end

    -- Simple concatenation (cache_control stripped: OpenAI doesn't support it)
    local parts = {}
    for _, block in ipairs(system) do
        if type(block) == "table" and block.type == "text"
                and type(block.text) == "string" then
            local cleaned = strip_cch_from_billing(block.text)
            if cleaned then
                table.insert(parts, cleaned)
            end
        end
    end
    local text = table.concat(parts, "")
    if text == "" then
        return nil
    end
    return { role = "system", content = text }
end


--- Convert an incoming Anthropic request to OpenAI Chat format.
function _M.convert_request(request_table, ctx)
    if type(request_table) ~= "table" then
        return nil, "request body must be a table"
    end

    if type(request_table.messages) ~= "table" or
       #request_table.messages == 0 then
        return nil, "missing messages"
    end

    -- Whitelist body construction: only explicitly converted fields are set.
    local openai_body = {}

    -- Model passthrough
    if type(request_table.model) == "string" then
        openai_body.model = request_table.model
    end

    -- Stream passthrough
    if request_table.stream ~= nil then
        openai_body.stream = request_table.stream
        if openai_body.stream then
            openai_body.stream_options = { include_usage = true }
        end
    end

    -- max_tokens → max_completion_tokens (never forward max_tokens)
    if request_table.max_tokens then
        openai_body.max_completion_tokens = request_table.max_tokens
    end

    -- Simple parameter passthrough
    if request_table.temperature then
        openai_body.temperature = request_table.temperature
    end
    if request_table.top_p then
        openai_body.top_p = request_table.top_p
    end

    -- stop_sequences → stop
    if type(request_table.stop_sequences) == "table" then
        openai_body.stop = request_table.stop_sequences
    end

    -- thinking → reasoning_effort
    if request_table.thinking then
        local effort = convert_thinking_config(request_table.thinking,
                                               request_table.output_config)
        if effort then
            openai_body.reasoning_effort = effort
        end
    end

    -- tool_choice conversion
    if request_table.tool_choice then
        local converted_tc = convert_tool_choice(request_table.tool_choice)
        if converted_tc then
            openai_body.tool_choice = converted_tc
        end
        -- disable_parallel_tool_use
        if type(request_table.tool_choice) == "table"
                and request_table.tool_choice.disable_parallel_tool_use == true then
            openai_body.parallel_tool_calls = false
        end
    end

    -- Structured outputs → response_format. The schema lives in the top-level
    -- `output_format` (beta) or in `output_config.format` (GA), both shaped as
    -- { type = "json_schema", schema = <json schema> }. `output_format` wins
    -- when both are present, matching LiteLLM's Anthropic adapter.
    local output_format = request_table.output_format
    if type(output_format) ~= "table" or next(output_format) == nil then
        if type(request_table.output_config) == "table" then
            output_format = request_table.output_config.format
        end
    end
    if type(output_format) == "table" and output_format.type == "json_schema"
            and type(output_format.schema) == "table" and next(output_format.schema) then
        -- Copy before normalizing: the schema belongs to the client's body
        local schema = core.table.deepcopy(output_format.schema)
        normalize_strict_schema(schema)
        openai_body.response_format = {
            type = "json_schema",
            json_schema = {
                name = "structured_output",
                schema = schema,
                strict = true,
            },
        }
    end

    -- metadata.user_id → user
    if type(request_table.metadata) == "table"
            and type(request_table.metadata.user_id) == "string" then
        openai_body.user = request_table.metadata.user_id
    end

    -- service_tier passthrough
    if type(request_table.service_tier) == "string" then
        openai_body.service_tier = request_table.service_tier
    end

    -- 1. Convert tools (only when non-empty)
    local tool_name_map = {}
    if type(request_table.tools) == "table" and #request_table.tools > 0 then
        local openai_tools = {}
        local declared_names = {}
        for _, tool in ipairs(request_table.tools) do
            if type(tool) ~= "table" then
                goto CONTINUE_TOOL
            end

            if is_builtin_tool(tool) then
                core.log.debug("dropping Anthropic built-in tool '", tool.type,
                               "': not supported by OpenAI upstream")
                goto CONTINUE_TOOL
            end

            if type(tool.name) ~= "string" or tool.name == "" then
                goto CONTINUE_TOOL
            end

            local oai_name = openai_tool_name(tool.name, tool_name_map)
            declared_names[tool.name] = oai_name
            local oai_tool = {
                type = "function",
                ["function"] = {
                    name = oai_name,
                    description = tool.description,
                    parameters = tool.input_schema,
                },
            }
            table.insert(openai_tools, oai_tool)
            ::CONTINUE_TOOL::
        end
        if #openai_tools > 0 then
            openai_body.tools = openai_tools
        end
        -- Point tool_choice at the name the tool was declared with. A name that
        -- matches no declared tool is left alone: renaming it would only invent
        -- a mapping for a tool the upstream never saw.
        if type(openai_body.tool_choice) == "table"
                and openai_body.tool_choice.type == "function" then
            local tc_func = openai_body.tool_choice["function"]
            if tc_func and type(tc_func.name) == "string" then
                tc_func.name = declared_names[tc_func.name] or tc_func.name
            end
        end
    end

    -- 2. System prompt
    local messages = {}
    if request_table.system then
        local sys_msg = convert_system(request_table.system)
        if sys_msg then
            table.insert(messages, sys_msg)
        end
    end

    -- 3. Convert messages
    for i, msg in ipairs(request_table.messages) do
        if type(msg) ~= "table" or type(msg.role) ~= "string" then
            return nil, "invalid message at index " .. i
        end

        if type(msg.content) == "string" then
            table.insert(messages, { role = msg.role, content = msg.content })
            goto CONTINUE
        end

        if type(msg.content) ~= "table" then
            return nil, "invalid message content at index " .. i
        end

        -- Process content block array
        local tool_calls = {}
        local tool_results = {}
        local content_parts = {}

        for _, block in ipairs(msg.content) do
            if type(block) ~= "table" then
                core.log.warn("unexpected non-table content block in Anthropic ",
                              "request, skipping: ", tostring(block))
                goto CONTINUE_BLOCK
            end

            if block.type == "text" and type(block.text) == "string" then
                local text_part = { type = "text", text = block.text }
                table.insert(content_parts, text_part)

            elseif block.type == "image" or block.type == "document" then
                local media_part = convert_media_block(block)
                if media_part then
                    table.insert(content_parts, media_part)
                end

            elseif block.type == "tool_use" then
                if type(block.id) == "string" and type(block.name) == "string" then
                    table.insert(tool_calls, {
                        id = block.id,
                        type = "function",
                        ["function"] = {
                            name = openai_tool_name(block.name, tool_name_map),
                            arguments = core.json.encode(block.input or {})
                        }
                    })
                end

            elseif block.type == "tool_result" then
                if type(block.tool_use_id) == "string" then
                    local tr_content
                    if type(block.content) == "string" then
                        tr_content = block.content
                    elseif type(block.content) == "table" then
                        -- Extract text from content array; images become image_url
                        local texts = {}
                        local parts = {}
                        local has_media = false
                        for _, sub in ipairs(block.content) do
                            if type(sub) == "table" then
                                if sub.type == "text" and type(sub.text) == "string" then
                                    table.insert(texts, sub.text)
                                    table.insert(parts, { type = "text", text = sub.text })
                                elseif sub.type == "image" or sub.type == "document" then
                                    local mp = convert_media_block(sub)
                                    if mp then
                                        table.insert(parts, mp)
                                        has_media = true
                                    end
                                end
                            end
                        end
                        if has_media then
                            tr_content = parts
                        else
                            tr_content = table.concat(texts, "")
                        end
                    else
                        tr_content = ""
                    end
                    table.insert(tool_results, {
                        role = "tool",
                        tool_call_id = block.tool_use_id,
                        content = tr_content,
                    })
                end

            -- thinking/redacted_thinking blocks are dropped: OpenAI Chat Completions
            -- has no equivalent semantics for past reasoning content as input.
            -- This is a protocol limitation, not a bug.
            end

            ::CONTINUE_BLOCK::
        end

        -- Emit tool_results as separate messages. OpenAI requires every `tool`
        -- message to immediately follow the assistant message that carries the
        -- matching tool_calls, so anything else in this Anthropic message has
        -- to be emitted after them, not before.
        if #tool_results > 0 then
            for _, tr in ipairs(tool_results) do
                table.insert(messages, tr)
            end

            if #content_parts > 0 then
                table.insert(messages, { role = msg.role, content = content_parts })
            end
            goto CONTINUE
        end

        -- Build the message
        local new_msg = { role = msg.role }

        if #tool_calls > 0 then
            new_msg.tool_calls = tool_calls
            -- Text content alongside tool_calls
            local text = concat_text_parts(content_parts)
            new_msg.content = text ~= "" and text or nil
        elseif #content_parts == 0 then
            new_msg.content = ""
        elseif msg.role == "assistant" then
            -- An assistant turn only ever carries text; OpenAI takes it as a string
            new_msg.content = concat_text_parts(content_parts)
        else
            -- A user turn can mix text with media, so it stays a content array
            new_msg.content = content_parts
        end

        table.insert(messages, new_msg)
        ::CONTINUE::
    end
    openai_body.messages = messages

    -- Store tool name mapping in ctx for response restoration
    if next(tool_name_map) then
        ctx.anthropic_tool_name_map = tool_name_map
    end

    -- tool_choice and parallel_tool_calls are only valid alongside a non-empty
    -- tools array. If no tools are forwarded to the upstream -- either none were
    -- provided or all were dropped (Anthropic built-ins / invalid) -- drop them
    -- to avoid the OpenAI-compatible upstream rejecting the request.
    if openai_body.tools == nil then
        openai_body.tool_choice = nil
        openai_body.parallel_tool_calls = nil
    end

    return openai_body
end


--- Convert an OpenAI response back to Anthropic format.
function _M.convert_response(res_body, ctx)
    if type(res_body) ~= "table" then
        return nil, "response body must be a table"
    end

    -- Error passthrough: convert upstream errors to Anthropic error format
    if res_body.error then
        local err_obj = res_body.error
        local err_type = "api_error"
        if type(err_obj) == "table" then
            if err_obj.type then
                err_type = err_obj.type
            elseif err_obj.code then
                err_type = err_obj.code
            end
        end
        local err_msg = ""
        if type(err_obj) == "table" and type(err_obj.message) == "string" then
            err_msg = err_obj.message
        elseif type(err_obj) == "string" then
            err_msg = err_obj
        end
        return {
            type = "error",
            error = {
                type = err_type,
                message = err_msg,
            },
        }
    end

    local choice = res_body.choices and res_body.choices[1]
    if not choice then
        return nil, "no choices in response"
    end

    local model = ctx.var.llm_model

    local content = {}

    -- Extract reasoning/thinking from response
    local msg = choice.message
    if msg then
        local reasoning = msg.reasoning_content or msg.reasoning
        if type(reasoning) == "string" and reasoning ~= "" then
            table.insert(content, {
                type = "thinking",
                thinking = reasoning,
                signature = "",
            })
        end
    end

    -- Text content
    local text = msg and msg.content
    if type(text) == "string" and text ~= "" then
        table.insert(content, { type = "text", text = text })
    end

    -- Tool calls
    local tool_name_map = ctx.anthropic_tool_name_map
    if msg and type(msg.tool_calls) == "table" then
        for _, tc in ipairs(msg.tool_calls) do
            local input = {}
            if tc["function"] and type(tc["function"].arguments) == "string" then
                local decoded, err = core.json.decode(tc["function"].arguments)
                if type(decoded) ~= "table" then
                    -- Upstream returned malformed or non-object tool_call
                    -- arguments. Don't abort the whole response conversion --
                    -- that would also drop already-collected text/thinking
                    -- content; fall back to an empty object and log instead.
                    core.log.warn("anthropic converter: failed to decode ",
                                  "tool_call arguments, using empty input: ",
                                  err or "not a JSON object")
                    decoded = {}
                end
                input = decoded
            end
            local tc_name = (tc["function"] and tc["function"].name) or ""
            -- Restore original Anthropic tool name if it was sanitized
            if tool_name_map and tool_name_map[tc_name] then
                tc_name = tool_name_map[tc_name]
            end
            table.insert(content, {
                type = "tool_use",
                id = tc.id or "",
                name = tc_name,
                input = input,
            })
        end
    end

    if #content == 0 then
        content = {{ type = "text", text = "" }}
    end

    -- Usage with cached_tokens handling
    local usage = {
        input_tokens = 0,
        output_tokens = 0,
    }
    if res_body.usage then
        local prompt_tokens = res_body.usage.prompt_tokens or 0
        local completion_tokens = res_body.usage.completion_tokens or 0
        local details = res_body.usage.prompt_tokens_details

        usage.output_tokens = completion_tokens

        if type(details) == "table" then
            local cached = details.cached_tokens or 0
            usage.input_tokens = math_max(0, prompt_tokens - cached)
            usage.cache_read_input_tokens = cached
            if details.cache_creation_input_tokens then
                usage.cache_creation_input_tokens = details.cache_creation_input_tokens
            end
        else
            usage.input_tokens = prompt_tokens
        end
    end

    local anthropic_res = {
        id = res_body.id,
        type = "message",
        role = "assistant",
        model = model or res_body.model,
        content = content,
        stop_reason = openai_stop_reason_map[choice.finish_reason] or "end_turn",
        usage = usage,
    }

    return anthropic_res
end


--- Convert an OpenAI SSE chunk to Anthropic SSE events.
local function openai_to_anthropic_sse(openai_chunk, state, tool_name_map)
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
                local details = openai_chunk.usage.prompt_tokens_details
                local prompt_tokens = openai_chunk.usage.prompt_tokens or 0
                local cached = 0
                if type(details) == "table" then
                    cached = details.cached_tokens or 0
                end
                message_delta.usage = {
                    input_tokens  = math_max(0, prompt_tokens - cached),
                    output_tokens = openai_chunk.usage.completion_tokens or 0,
                }
                if cached > 0 then
                    message_delta.usage.cache_read_input_tokens = cached
                end
                if type(details) == "table" and details.cache_creation_input_tokens then
                    message_delta.usage.cache_creation_input_tokens =
                        details.cache_creation_input_tokens
                end
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
            usage = { input_tokens = 0, output_tokens = 0 },
        }
        setmetatable(message.content, core.json.array_mt)

        table.insert(events, make_sse_event("message_start", {
            type = "message_start",
            message = message,
        }))

        state.is_first = false
        state.next_content_index = 0
        state.current_open_block = nil
        state.current_block_type = nil
        state.tool_call_indices = {}
    end

    -- Normalize finish_reason: nil, empty, "null", whitespace → no finish
    local finish_reason
    if choice then
        local fr = choice.finish_reason
        if type(fr) == "string" then
            local trimmed = fr:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" and trimmed ~= "null" then
                finish_reason = trimmed
            end
        end
    end

    -- 2. Handle reasoning/thinking content delta
    if choice and choice.delta then
        local reasoning = choice.delta.reasoning_content or choice.delta.reasoning
        if type(reasoning) == "string" and reasoning ~= "" then
            -- Start thinking block if not already open
            if state.current_block_type ~= "thinking" then
                if state.current_open_block ~= nil then
                    push_content_block_stop(events, state.current_open_block)
                end
                local idx = state.next_content_index
                state.next_content_index = idx + 1
                state.current_open_block = idx
                state.current_block_type = "thinking"
                push_content_block_start(events, idx, {
                    type = "thinking",
                    thinking = "",
                })
            end
            push_content_block_delta(events, state.current_open_block, {
                type = "thinking_delta",
                thinking = reasoning,
            })
        end
    end

    -- 3. Handle text content delta
    if choice and choice.delta and type(choice.delta.content) == "string"
            and choice.delta.content ~= "" then
        -- Transition from thinking to text block if needed
        if state.current_block_type ~= "text" then
            if state.current_open_block ~= nil then
                push_content_block_stop(events, state.current_open_block)
            end
            local idx = state.next_content_index
            state.next_content_index = idx + 1
            state.current_open_block = idx
            state.current_block_type = "text"
            push_content_block_start(events, idx, { type = "text", text = "" })
        end
        push_content_block_delta(events, state.current_open_block, {
            type = "text_delta",
            text = choice.delta.content,
        })
    end

    -- 4. Handle tool_calls deltas
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
                local idx = state.next_content_index
                state.next_content_index = idx + 1
                state.tool_call_indices[tc_idx] = idx
                state.current_open_block = idx
                state.current_block_type = "tool_use"

                local fn = tc_delta["function"] or {}
                local tool_name = fn.name or ""
                if tool_name_map and tool_name_map[tool_name] then
                    tool_name = tool_name_map[tool_name]
                end
                push_content_block_start(events, idx, {
                    type  = "tool_use",
                    id    = tc_delta.id or "",
                    name  = tool_name,
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

    -- 5. Handle stream completion (only when finish_reason is valid)
    if finish_reason then
        if state.current_open_block ~= nil then
            push_content_block_stop(events, state.current_open_block)
            state.current_open_block = nil
            state.current_block_type = nil
        end

        local message_delta = {
            type = "message_delta",
            delta = {
                stop_reason = openai_stop_reason_map[finish_reason] or "end_turn",
            },
        }

        if type(openai_chunk.usage) == "table" then
            local details = openai_chunk.usage.prompt_tokens_details
            local prompt_tokens = openai_chunk.usage.prompt_tokens or 0
            local cached = 0
            if type(details) == "table" then
                cached = details.cached_tokens or 0
            end
            message_delta.usage = {
                input_tokens  = math_max(0, prompt_tokens - cached),
                output_tokens = openai_chunk.usage.completion_tokens or 0,
            }
            if cached > 0 then
                message_delta.usage.cache_read_input_tokens = cached
            end
        end

        state.pending_message_delta = message_delta
        state.pending_stop = true
        state.is_done = true
    end

    return events
end


--- Convert parsed SSE events (from openai-chat adapter) to Anthropic format.
function _M.convert_sse_events(parsed, ctx, state)
    if not parsed or parsed.type == "skip" then
        return nil
    end

    -- Pass-through ping events to keep long-lived connections alive
    if parsed.type == "ping" then
        return { make_sse_event("ping", { type = "ping" }) }
    end

    if parsed.type == "done" then
        -- Flush any deferred message_stop
        if state.pending_stop then
            return openai_to_anthropic_sse({ choices = {} }, state,
                                           ctx and ctx.anthropic_tool_name_map)
        end
        -- If no pending_stop but stream never finished properly, emit minimal stop.
        -- message_start may have been sent without ever opening a content block,
        -- so emit message_stop regardless to avoid leaving the client hanging.
        if not state.is_done and state.is_first == false then
            local events = {}
            if state.current_open_block ~= nil then
                push_content_block_stop(events, state.current_open_block)
                state.current_open_block = nil
            end
            local message_delta = {
                type = "message_delta",
                delta = { stop_reason = "end_turn" },
                usage = { input_tokens = 0, output_tokens = 0 },
            }
            table.insert(events, make_sse_event("message_delta", message_delta))
            table.insert(events, make_sse_event("message_stop", { type = "message_stop" }))
            state.is_done = true
            return events
        end
        return nil
    end

    if parsed.data then
        return openai_to_anthropic_sse(parsed.data, state,
                                       ctx and ctx.anthropic_tool_name_map)
    end

    return nil
end


--- Convert headers for the upstream request.
-- Transforms Anthropic-specific headers to OpenAI-compatible format.
function _M.convert_headers(headers)
    if type(headers) ~= "table" then
        return
    end

    -- Convert x-api-key to Authorization Bearer (if no Authorization already set)
    local api_key = headers["x-api-key"]
    if type(api_key) == "string" and api_key ~= "" then
        if not headers["authorization"] then
            headers["authorization"] = "Bearer " .. api_key
        end
        headers["x-api-key"] = nil
    end

    -- Remove Anthropic-specific and SDK telemetry headers
    local to_remove = {}
    for k in pairs(headers) do
        if type(k) == "string" then
            if k:sub(1, 10) == "anthropic-" or k:sub(1, 12) == "x-stainless-" then
                table.insert(to_remove, k)
            end
        end
    end
    for _, k in ipairs(to_remove) do
        headers[k] = nil
    end
end


return _M
