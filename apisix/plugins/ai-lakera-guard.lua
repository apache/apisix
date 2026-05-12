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


local plugin_name = "ai-lakera-guard"

local _M = {
    version = 0.1,
    priority = 1028,
    name = plugin_name,
    schema = schema_mod.schema,
}


function _M.check_schema(conf)
    return schema_mod.check_schema(conf)
end


local function set_scan_info(ctx, detector_types)
    local info, err = core.json.encode({
        flagged = true,
        detector_types = detector_types or {},
    })
    if not info then
        core.log.warn("ai-lakera-guard: failed to encode scan info: ", err)
        return
    end
    ctx.var.lakera_guard_scan_info = info
end


local function build_deny_body(conf, ctx, detector_types)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        core.log.error("ai-lakera-guard: unsupported protocol: ",
                       ctx.ai_client_protocol or "unknown")
        return conf.on_block.message
    end
    local text = conf.on_block.message
    if conf.reveal_failure_categories and detector_types and #detector_types > 0 then
        text = text .. ". Flagged categories: " .. table.concat(detector_types, ", ")
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


-- Run a Lakera scan over `content` and translate the verdict into one of:
--   "pass"  — forward the chunk/response unchanged
--   "alert" — flagged but configured to alert only (warn + observability already done)
--   "deny"  — caller must short-circuit with the returned deny body
local function scan_and_decide(conf, ctx, content)
    local lakera_messages = { { role = "assistant", content = content } }
    local flagged, detector_types, scan_err = client.scan(conf, lakera_messages,
                                                          conf.project_id)
    if scan_err then
        if conf.fail_open then
            core.log.warn("ai-lakera-guard: response scan failed, ",
                          "fail_open=true so proceeding: ", scan_err)
            return "pass"
        end
        core.log.error("ai-lakera-guard: response scan failed: ", scan_err)
        return "deny", build_deny_body(conf, ctx, nil)
    end

    if flagged then
        set_scan_info(ctx, detector_types)
        if conf.action == "alert" then
            core.log.warn("ai-lakera-guard: flagged in alert mode, detector_types: ",
                          table.concat(detector_types or {}, ","))
            return "alert"
        end
        return "deny", build_deny_body(conf, ctx, detector_types)
    end

    return "pass"
end


function _M.access(conf, ctx)
    if conf.direction == "output" then
        return
    end

    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return 400, err
    end

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.extract_request_content then
        core.log.warn("ai-lakera-guard: unsupported protocol: ",
                      ctx.ai_client_protocol or "unknown")
        return
    end

    local contents = proto.extract_request_content(request_tab)
    if not contents or #contents == 0 then
        core.log.warn("ai-lakera-guard: empty extracted content for protocol: ",
                      ctx.ai_client_protocol)
        return
    end

    local lakera_messages = core.table.new(#contents, 0)
    for _, content in ipairs(contents) do
        core.table.insert(lakera_messages, { role = "user", content = content })
    end

    local flagged, detector_types, scan_err = client.scan(conf, lakera_messages,
                                                          conf.project_id)
    local deny_content_type = ctx.var.request_type == "ai_stream"
                                  and "text/event-stream"
                                  or "application/json"
    if scan_err then
        if conf.fail_open then
            core.log.warn("ai-lakera-guard: scan failed, fail_open=true so proceeding: ",
                          scan_err)
            return
        end
        core.log.error("ai-lakera-guard: scan failed: ", scan_err)
        core.response.set_header("Content-Type", deny_content_type)
        return conf.on_block.status, build_deny_body(conf, ctx, nil)
    end

    if flagged then
        set_scan_info(ctx, detector_types)
        if conf.action == "alert" then
            core.log.warn("ai-lakera-guard: flagged in alert mode, detector_types: ",
                          table.concat(detector_types or {}, ","))
            return
        end
        core.response.set_header("Content-Type", deny_content_type)
        return conf.on_block.status, build_deny_body(conf, ctx, detector_types)
    end
end


function _M.lua_body_filter(conf, ctx, headers, body)
    if conf.direction == "input" then
        return
    end

    if ngx.status >= 400 then
        core.log.info("ai-lakera-guard: skip response scan, upstream status: ",
                      ngx.status)
        return
    end

    local request_type = ctx.var.request_type

    if request_type == "ai_chat" then
        local content = ctx.var.llm_response_text
        if not content or content == "" then
            return
        end
        local decision, deny_body = scan_and_decide(conf, ctx, content)
        if decision == "deny" then
            return ngx.OK, deny_body
        end
        return
    end

    if request_type ~= "ai_stream" then
        return
    end

    if ctx.lakera_denied then
        return ngx.OK, ""
    end

    local now_ms = ngx.now() * 1000
    if not ctx.lakera_last_flush_ms then
        ctx.lakera_last_flush_ms = now_ms
    end
    ctx.lakera_buffer = ctx.lakera_buffer or {}
    ctx.lakera_buffer_size = ctx.lakera_buffer_size or 0
    if ctx.llm_response_contents_in_chunk then
        for _, text in ipairs(ctx.llm_response_contents_in_chunk) do
            core.table.insert(ctx.lakera_buffer, text)
            ctx.lakera_buffer_size = ctx.lakera_buffer_size + #text
        end
    end

    local size_trigger = ctx.lakera_buffer_size >= conf.response_buffer_size
    local age_trigger = (now_ms - ctx.lakera_last_flush_ms)
                            >= conf.response_buffer_max_age_ms
    local done_trigger = ctx.var.llm_request_done
    if not (size_trigger or age_trigger or done_trigger) then
        return
    end

    if ctx.lakera_buffer_size == 0 then
        ctx.lakera_last_flush_ms = now_ms
        return
    end

    local content = table.concat(ctx.lakera_buffer)
    ctx.lakera_buffer = {}
    ctx.lakera_buffer_size = 0
    ctx.lakera_last_flush_ms = now_ms
    local decision, deny_body = scan_and_decide(conf, ctx, content)
    if decision == "deny" then
        ctx.lakera_denied = true
        return ngx.OK, deny_body
    end
end


function _M.log(conf, ctx)
    return
end


return _M
