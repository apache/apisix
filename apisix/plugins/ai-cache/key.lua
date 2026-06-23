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

local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")
local sha256    = require("resty.sha256")
local to_hex    = require("resty.string").to_hex

local ipairs = ipairs
local pairs  = pairs
local concat = table.concat

local _M = {}


local function hex_digest(s)
    local hash = sha256:new()
    hash:update(s)
    return to_hex(hash:final())
end


function _M.fingerprint(ctx, body)
    local params = {}
    for k, v in pairs(body) do
        if k ~= "messages" and k ~= "model" and k ~= "stream" then
            params[k] = v
        end
    end

    local repr = core.json.canonical_encode({
        protocol = ctx.ai_client_protocol or "",
        model    = ctx.var.request_llm_model or body.model or "",
        messages = protocols.get_messages(body, ctx) or {},
        params   = params,
    })
    return hex_digest(repr)
end


function _M.scope(conf, ctx)
    local ck = conf.cache_key or {}

    local parts = {}
    if not ck.share_across_routes then
        parts[#parts + 1] = "route=" .. (ctx.var.route_id or "")
    end
    if ck.include_consumer then
        parts[#parts + 1] = "consumer=" .. (ctx.consumer_name or "")
    end
    if ck.include_vars then
        for _, name in ipairs(ck.include_vars) do
            parts[#parts + 1] = name .. "=" .. (ctx.var[name] or "")
        end
    end

    if #parts == 0 then
        return "shared"
    end
    return concat(parts, ":")
end


return _M
