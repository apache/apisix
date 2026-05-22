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

local core        = require("apisix.core")
local schema_mod  = require("apisix.plugins.ai-cache.schema")
local protocols   = require("apisix.plugins.ai-protocols")
local openai_chat = require("apisix.plugins.ai-protocols.openai-chat")
local key_mod     = require("apisix.plugins.ai-cache.key")
local ngx         = ngx

local plugin_name = "ai-cache"

-- Hardcoded in PR-1; PR-5 makes this a schema field.
local STATUS_HEADER = "X-AI-Cache-Status"

local _M = {
    -- ai-proxy = 1040, ai-proxy-multi = 1041, proxy-cache = 1085.
    -- ai-cache must run before ai-proxy so a hit can short-circuit
    -- before the upstream request is built (RFC § 2.3).
    version        = 0.1,
    priority       = 1086,
    name           = plugin_name,
    schema         = schema_mod.schema,
    encrypt_fields = schema_mod.encrypt_fields,
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.access(conf, ctx)
    local body, body_err = core.request.get_json_request_body_table()
    if not body then
        core.log.debug("ai-cache: request body not JSON (", body_err,
                       "); deferring to ai-proxy")
        return
    end

    local protocol = protocols.detect(body, ctx)
    if protocol ~= "openai-chat" then
        return
    end
    ctx.ai_client_protocol = protocol

    if openai_chat.is_streaming(body) then
        core.response.set_header(STATUS_HEADER, "SKIP-STREAM")
        return
    end

    -- Build the key & stash for log-phase write. (Hit path lands in Task 8.)
    local key = key_mod.build(body)
    ctx.ai_cache = { key = key, started_at = ngx.now() }
    core.response.set_header(STATUS_HEADER, "MISS")
end


return _M
