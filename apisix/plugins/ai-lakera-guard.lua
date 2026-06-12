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
local ipairs     = ipairs


local plugin_name = "ai-lakera-guard"


local _M = {
    version  = 0.1,
    priority = 1028,
    name     = plugin_name,
    schema   = schema_mod.schema,
}


function _M.check_schema(conf)
    return schema_mod.check_schema(conf)
end


function _M.access(conf, ctx)
    if not ctx.ai_client_protocol then
        return 500, "ai-lakera-guard plugin must be used with " ..
                    "ai-proxy or ai-proxy-multi plugin"
    end

    if ctx.ai_client_protocol ~= "openai-chat" then
        core.log.warn("ai-lakera-guard: protocol ", ctx.ai_client_protocol,
                      " not yet supported in this build; skipping scan")
        return
    end

    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return 400, err
    end

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.extract_request_content then
        core.log.warn("ai-lakera-guard: protocol module missing for ",
                      ctx.ai_client_protocol)
        return
    end

    local contents = proto.extract_request_content(request_tab)
    if not contents or #contents == 0 then
        core.log.warn("ai-lakera-guard: empty extracted content for protocol ",
                      ctx.ai_client_protocol)
        return
    end

    local lakera_messages = core.table.new(#contents, 0)
    for _, content in ipairs(contents) do
        core.table.insert(lakera_messages, { role = "user", content = content })
    end

    local flagged, _, scan_err = client.scan(conf, lakera_messages, nil)

    local function build_deny()
        return proto.build_deny_response({
            text   = conf.on_block.message,
            model  = ctx.var.request_llm_model,
            usage  = proto.empty_usage and proto.empty_usage()
                        or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 },
            stream = ctx.var.request_type == "ai_stream",
        })
    end

    local function set_content_type()
        core.response.set_header("Content-Type",
            ctx.var.request_type == "ai_stream"
                and "text/event-stream"
                or "application/json")
    end

    if scan_err then
        core.log.error("ai-lakera-guard: scan failed: ", scan_err)
        set_content_type()
        return conf.on_block.status, build_deny()
    end

    if flagged then
        set_content_type()
        return conf.on_block.status, build_deny()
    end
end


return _M
