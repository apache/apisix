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


local function build_deny_body(conf, ctx)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        core.log.error("ai-lakera-guard: unsupported protocol: ",
                       ctx.ai_client_protocol or "unknown")
        return conf.on_block.message
    end
    local usage = ctx.llm_raw_usage
        or (proto.empty_usage and proto.empty_usage())
        or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    return proto.build_deny_response({
        text = conf.on_block.message,
        model = ctx.var.request_llm_model,
        usage = usage,
        stream = ctx.var.request_type == "ai_stream",
    })
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
    if scan_err then
        core.log.error("ai-lakera-guard: scan failed: ", scan_err)
        return
    end

    if flagged then
        set_scan_info(ctx, detector_types)
        core.response.set_header("Content-Type", "application/json")
        return conf.on_block.status, build_deny_body(conf, ctx)
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

    if ctx.var.request_type ~= "ai_chat" then
        return
    end

    local content = ctx.var.llm_response_text
    if not content or content == "" then
        return
    end

    local lakera_messages = { { role = "assistant", content = content } }
    local flagged, detector_types, scan_err = client.scan(conf, lakera_messages,
                                                          conf.project_id)
    if scan_err then
        core.log.error("ai-lakera-guard: response scan failed: ", scan_err)
        return
    end

    if flagged then
        set_scan_info(ctx, detector_types)
        return ngx.OK, build_deny_body(conf, ctx)
    end
end


function _M.log(conf, ctx)
    return
end


return _M
