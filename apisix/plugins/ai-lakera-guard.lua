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


local function request_content_moderation(ctx, conf, content)
    if not content or #content == 0 then
        return
    end

    local result, err = client.scan(conf, content)
    if err then
        if conf.fail_open then
            core.log.warn("ai-lakera-guard: ", err, "; fail_open=true, allowing request")
            return
        end
        core.log.error("ai-lakera-guard: ", err, "; fail_open=false, blocking request")
        return conf.deny_code, deny_message(ctx, conf, conf.request_failure_message)
    end

    if not result.flagged then
        return
    end

    -- Log Lakera's full per-detector verdict (every entry, detected or not) so
    -- both alert mode and blocked requests are auditable.
    core.log.warn("ai-lakera-guard: request flagged by Lakera Guard",
                  ", breakdown: ", core.json.encode(result.breakdown),
                  ", request_uuid: ", result.request_uuid or "")

    if conf.action == "alert" then
        return
    end

    return conf.deny_code, deny_message(ctx, conf, conf.request_failure_message, result.breakdown)
end


function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        return 500, "no ai instance picked, ai-lakera-guard plugin must be used with "
                    .. "ai-proxy or ai-proxy-multi plugin"
    end

    -- ai-proxy / ai-proxy-multi runs first (higher priority) and already
    -- validated the Content-Type and parsed the JSON body -- it rejects non-JSON
    -- before picking an instance, so reaching here guarantees a valid JSON table.
    local request_tab = core.request.get_json_request_body_table()

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.extract_request_content then
        return 500, "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown")
    end

    local contents = proto.extract_request_content(request_tab)
    local content_to_check = concat(contents, " ")

    local code, message = request_content_moderation(ctx, conf, content_to_check)
    if code then
        if ctx.var.request_type == "ai_stream" then
            core.response.set_header("Content-Type", "text/event-stream")
        else
            core.response.set_header("Content-Type", "application/json")
        end
        return code, message
    end
end


return _M
