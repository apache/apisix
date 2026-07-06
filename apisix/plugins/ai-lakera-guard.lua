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
local core       = require("apisix.core")
local schema_mod = require("apisix.plugins.ai-lakera-guard.schema")
local client     = require("apisix.plugins.ai-lakera-guard.client")
local protocols  = require("apisix.plugins.ai-protocols")
local binding    = require("apisix.plugins.ai-protocols.binding")

local ngx    = ngx
local ipairs = ipairs
local type   = type
local concat = table.concat


local _M = {
    version  = 0.1,
    priority = 1028,
    name     = "ai-lakera-guard",
    schema   = schema_mod.schema,
}


function _M.check_schema(conf)
    return schema_mod.check_schema(conf)
end


-- Format only the detectors that actually fired (detected = true) for the
-- client-facing reveal; the raw breakdown may also carry non-detected entries,
-- which belong in the log but not in the deny message.
local function format_breakdown(breakdown)
    local parts = {}
    for _, entry in ipairs(breakdown or {}) do
        if type(entry) == "table" and entry.detected and entry.detector_type then
            local part = entry.detector_type
            if entry.result and entry.result ~= "" then
                part = part .. " (" .. entry.result .. ")"
            end
            core.table.insert(parts, part)
        end
    end
    return parts
end


local function deny_message(ctx, conf, message, breakdown)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        core.log.error("ai-lakera-guard: unsupported protocol: ",
                       ctx.ai_client_protocol or "unknown")
        return message
    end
    local text = message
    if conf.reveal_failure_categories then
        local parts = format_breakdown(breakdown)
        if #parts > 0 then
            text = text .. ". Flagged categories: " .. concat(parts, ", ")
        end
    end
    local usage = ctx.llm_raw_usage
        or (proto.empty_usage and proto.empty_usage())
        or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    return proto.build_deny_response({
        text = text,
        model = ctx.var.request_llm_model,
        usage = usage,
        stream = ctx.var.request_type == "ai_stream",
    })
end


-- get_messages returns canonical {role, content} with content already flattened
-- to a string; drop turns without a role or with nothing for Lakera to scan.
local function normalize_messages(messages)
    local out = {}
    for _, message in ipairs(messages) do
        if type(message.role) == "string" and message.content ~= "" then
            core.table.insert(out, message)
        end
    end
    return out
end


-- Scan a conversation with Lakera and decide what to do. Shared by the request
-- (input) and response (output) paths; `label` ("request"/"response") tailors the
-- logs and `failure_message` selects the direction-specific deny text. Returns
-- (deny_code, deny_body) when the traffic must be blocked, or nothing to allow.
local function moderate(ctx, conf, messages, label, failure_message)
    if not messages or #messages == 0 then
        return
    end

    local result, err = client.scan(conf, messages)
    if err then
        if conf.fail_open then
            core.log.warn("ai-lakera-guard: ", err, "; fail_open=true, allowing ", label)
            return
        end
        core.log.error("ai-lakera-guard: ", err, "; fail_open=false, blocking ", label)
        return conf.deny_code, deny_message(ctx, conf, failure_message)
    end

    if not result.flagged then
        return
    end

    -- Log Lakera's full per-detector verdict (every entry, detected or not) so
    -- both alert mode and blocked traffic are auditable.
    core.log.warn("ai-lakera-guard: ", label, " flagged by Lakera Guard",
                  ", breakdown: ", core.json.encode(result.breakdown),
                  ", request_uuid: ", result.request_uuid or "")

    if conf.action == "alert" then
        return
    end

    return conf.deny_code, deny_message(ctx, conf, failure_message, result.breakdown)
end


local function moderate_response(ctx, conf, text)
    return moderate(ctx, conf, { { role = "assistant", content = text } },
                    "response", conf.response_failure_message)
end


function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "no ai instance picked (request did not pass through ai-proxy/ai-proxy-multi)",
            500, "no ai instance picked, ai-lakera-guard plugin must be used with "
                 .. "ai-proxy or ai-proxy-multi plugin")
        if handled then
            return code, body
        end
        return
    end

    if conf.direction == "output" then
        return
    end

    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "failed to read request body: " .. (err or "unknown error"),
            500, "failed to read request body: " .. (err or "unknown error"))
        if handled then
            return code, body
        end
        return
    end

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.get_messages then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"),
            500, "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"))
        if handled then
            return code, body
        end
        return
    end

    local messages = normalize_messages(proto.get_messages(request_tab))
    if #messages == 0 and proto.extract_request_content then
        -- The protocol has no role-preserving representation for this body;
        -- fall back to a single user message built from the flat extraction.
        local text = concat(proto.extract_request_content(request_tab), " ")
        if text ~= "" then
            messages = { { role = "user", content = text } }
        end
    end

    local code, message = moderate(ctx, conf, messages, "request", conf.request_failure_message)
    if code then
        if ctx.var.request_type == "ai_stream" then
            core.response.set_header("Content-Type", "text/event-stream")
        else
            core.response.set_header("Content-Type", "application/json")
        end
        return code, message
    end
end


function _M.lua_body_filter(conf, ctx, headers, body)
    if conf.direction ~= "output" and conf.direction ~= "both" then
        return
    end

    if ngx.status >= 400 then
        return
    end

    -- Non-streaming: ai-proxy hands us the fully-assembled completion text.
    if ctx.var.request_type == "ai_chat" then
        local text = ctx.var.llm_response_text
        if not text or text == "" then
            return
        end
        return moderate_response(ctx, conf, text)
    end

    if ctx.var.request_type == "ai_stream" then
        if conf.action == "alert" and conf.fail_open then
            if ctx.var.llm_request_done and not ctx.lakera_response_decided then
                ctx.lakera_response_decided = "clean"
                local text = ctx.var.llm_response_text
                if text and text ~= "" then
                    moderate_response(ctx, conf, text)
                else
                    core.log.info("ai-lakera-guard: alert mode could not scan the ",
                                  "streamed response (no assembled completion)")
                end
            end
            return
        end

        -- block mode
        local buffer = ctx.lakera_response_buffer
        if not buffer then
            buffer = {}
            ctx.lakera_response_buffer = buffer
        end

        if ctx.lakera_response_decided then
            if ctx.lakera_response_decided == "blocked" then
                return nil, ":\n\n"
            end
            return
        end

        buffer[#buffer + 1] = body or ""

        if not ctx.var.llm_request_done then
            -- Withhold this chunk until end-of-stream, replacing it with an SSE
            -- keep-alive comment. Not "" (nginx treats an empty body as nothing
            -- to flush) and not nil (which would let the original chunk reach
            -- the client) -- the keep-alive holds the content back while keeping
            -- the connection open.
            return nil, ":\n\n"
        end

        local text = ctx.var.llm_response_text
        if text == "" then
            ctx.lakera_response_decided = "clean"
            return nil, concat(buffer)
        end
        if not text then
            if conf.fail_open then
                core.log.warn("ai-lakera-guard: streamed response ended without ",
                              "an assembled completion (no upstream usage event?); ",
                              "fail_open=true, releasing unscanned")
                ctx.lakera_response_decided = "clean"
                return nil, concat(buffer)
            end
            core.log.error("ai-lakera-guard: streamed response ended without ",
                           "an assembled completion (no upstream usage event?); ",
                           "fail_open=false, blocking response")
            ctx.lakera_response_decided = "blocked"
            return ngx.OK, deny_message(ctx, conf, conf.response_failure_message)
        end

        local code, message = moderate_response(ctx, conf, text)
        if code then
            ctx.lakera_response_decided = "blocked"
            return ngx.OK, message
        end

        -- Clean: release the buffered stream verbatim, preserving SSE framing.
        ctx.lakera_response_decided = "clean"
        return nil, concat(buffer)
    end
end


return _M
