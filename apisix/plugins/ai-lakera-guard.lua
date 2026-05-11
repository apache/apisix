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
    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return 400, err
    end
    if type(request_tab.messages) ~= "table" then
        return
    end

    local flagged, _, scan_err = client.scan(conf, request_tab.messages, conf.project_id)
    if scan_err then
        core.log.error("ai-lakera-guard: scan failed: ", scan_err)
        return
    end

    if flagged then
        core.response.set_header("Content-Type", "application/json")
        return conf.on_block.status, build_deny_body(conf, ctx)
    end
end


function _M.lua_body_filter(conf, ctx, headers, body)
    return
end


function _M.log(conf, ctx)
    return
end


return _M
