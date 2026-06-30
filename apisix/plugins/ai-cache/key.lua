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

local ipairs   = ipairs
local pairs    = pairs
local concat   = table.concat
local tostring = tostring

local KEY_PREFIX = "ai-cache:l1:"

local _M = {}


local function hex_digest(s)
    local hash = sha256:new()
    hash:update(s)
    return to_hex(hash:final())
end


local function client_messages(ctx, body)
    local proto = ctx.ai_client_protocol and protocols.get(ctx.ai_client_protocol)
    if proto and proto.get_messages then
        return proto.get_messages(body) or {}
    end
    return {}
end


function _M.messages(ctx, body)
    return client_messages(ctx, body)
end


-- Build the canonical representable struct. `messages` is the message list
-- folded into the representation: the full client messages for the exact (L1)
-- fingerprint, or only the response-determining context the embedding does not
-- cover (system prompts, prior turns, RAG documents) for the semantic (L2)
-- partition. nil omits message text entirely.
local function build_repr(ctx, body, messages)
    local inst = ctx.picked_ai_instance
    local ov   = inst.override or {}

    local params = {}
    for k, v in pairs(body) do
        if k ~= "messages" and k ~= "model" and k ~= "stream" then
            params[k] = v
        end
    end

    return {
        client = {
            protocol = ctx.ai_client_protocol or "",
            messages = messages,
            params   = params,
        },
        effective = {
            provider    = inst.provider,
            -- effective model precedence mirrors ai-proxy/base.lua exactly:
            -- the instance's options.model wins over the client body model.
            model       = (inst.options and inst.options.model) or body.model or "",
            options     = inst.options,
            llm_options = ov.llm_options,
            request_body                = ov.request_body,
            request_body_force_override = ov.request_body_force_override,
            -- override.endpoint can carry a path/query that selects a different
            -- deployment or model (azure deployment, bedrock inference-profile
            -- ARN, vertex project/region/model), so it is response-determining.
            endpoint    = ov.endpoint,
        },
    }
end


-- Identity of the EFFECTIVE upstream request, reconstructed from access-time
-- inputs only.
--
--   final_upstream_body = build_request(client_body, ai_client_protocol,
--                                       instance{provider, options, override})
--
-- is deterministic, and ai-proxy builds it later (in before_proxy) so it cannot
-- be observed here. Hashing build_request's INPUTS therefore identifies its
-- output uniquely, without invoking the (side-effecting) builder. This is the
-- ONLY place request-determining data lives; scope() below is pure isolation.
function _M.fingerprint(ctx, body)
    local repr = build_repr(ctx, body, client_messages(ctx, body))
    return hex_digest(core.json.canonical_encode(repr))
end


-- Returns the SHA-256 hex digest of the effective context with message text
-- removed.  Queries that differ only in phrasing (same model/params/instance)
-- share one fingerprint, enabling semantic deduplication without storing the
-- raw prompt.
function _M.context_fingerprint(ctx, body)
    return hex_digest(core.json.canonical_encode(build_repr(ctx, body, nil)))
end


-- Percent-encode "%", ":" and "=" (in that order) in scope values so a request-controlled
-- include_vars value can't shift "name=value:" boundaries to forge another scope.
local function esc(v)
    return (tostring(v or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("=", "%%3D"))
end


local function scope(conf, ctx)
    local ck = conf.cache_key or {}

    local parts = {}
    if not ck.share_across_routes then
        parts[#parts + 1] = "route=" .. esc(ctx.var.route_id)
    end
    if ck.include_consumer then
        parts[#parts + 1] = "consumer=" .. esc(ctx.consumer_name)
    end
    if ck.include_vars then
        for _, name in ipairs(ck.include_vars) do
            parts[#parts + 1] = name .. "=" .. esc(ctx.var[name])
        end
    end

    if #parts == 0 then
        return "shared"
    end
    return concat(parts, ":")
end


function _M.partition(conf, ctx, body, context_messages)
    local context_repr = core.json.canonical_encode(build_repr(ctx, body, context_messages))
    return hex_digest(scope(conf, ctx) .. "|" .. context_repr)
end


function _M.build(conf, ctx, fingerprint)
    return KEY_PREFIX .. scope(conf, ctx) .. ":" .. fingerprint
end


return _M
