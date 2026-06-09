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

local core         = require("apisix.core")
local resty_sha256 = require("resty.sha256")
local str          = require("resty.string")
local math         = math

local _M = {}

local U32_MAX = 4294967295

-- Collapse a non-negative float to an integer in milli-units.
-- NaN and negatives map to 0; infinity and overflow saturate to U32_MAX.
-- Only safe for fields whose valid domain is non-negative (temperature,
-- top_p) — signed fields must NOT use this (negatives would all collide
-- onto 0). Mirrors aisix-cache, which quantises only temperature/top_p.
local function quantise_milli(v)
    if type(v) ~= "number" then
        return nil
    end
    if v ~= v then
        -- NaN
        return 0
    end
    if v < 0 then
        return 0
    end
    local s = v * 1000
    if s == math.huge or s > U32_MAX then
        return U32_MAX
    end
    return math.floor(s)
end

-- Fields excluded from the cache key. `stream` is gated out before any key is
-- built (streaming requests are never cached). The rest are caller/bookkeeping
-- fields that do not change the completion; excluding them lets semantically
-- identical requests from different callers share one cache entry.
local NON_KEYED_FIELDS = {
    stream         = true,
    user           = true,
    stream_options = true,
    store          = true,
    metadata       = true,
}

-- Build the fingerprint from the effective request body and optional
-- opts = { protocol, instance, route_id }.
--
-- Like aisix-cache, the WHOLE request body is hashed (minus NON_KEYED_FIELDS)
-- instead of a fixed whitelist, so any output-affecting field — including ones
-- OpenAI adds later — automatically scopes the key and can never silently
-- cross-cache. temperature/top_p are milli-quantised to absorb float-parse
-- noise; every other field is hashed at its exact value (signed penalties
-- included). protocol + instance + route_id scope the key because, unlike
-- aisix's global model routing, APISIX resolves the upstream per route, so the
-- same body on two routes may hit different upstreams.
local function fingerprint(req, opts)
    local body = {}
    for k, v in pairs(req) do
        if not NON_KEYED_FIELDS[k] then
            body[k] = v
        end
    end
    -- Quantise only the non-negative float fields, on the copy (never mutate
    -- the caller's body). Signed/other fields stay exact.
    if body.temperature ~= nil then
        body.temperature = quantise_milli(body.temperature)
    end
    if body.top_p ~= nil then
        body.top_p = quantise_milli(body.top_p)
    end
    return {
        body     = body,
        protocol = opts and opts.protocol or nil,
        instance = opts and opts.instance or nil,
        route_id = opts and opts.route_id or nil,
    }
end

-- _M.build(req, opts) -> "ai-cache:l1::<sha256hex>"
--   req  : effective request body table
--   opts : optional { protocol = <string>, instance = <string>,
--                     route_id = <string> }
function _M.build(req, opts)
    local fp = fingerprint(req, opts)
    local canonical = core.json.stably_encode(fp)
    local sha = resty_sha256:new()
    sha:update(canonical)
    local hex = str.to_hex(sha:final())
    -- "ai-cache:l1:<scope>:<request>" — the scope segment stays empty in PR1
    -- (instance/protocol/route_id are folded into the hash); a later phase may
    -- fill it with a consumer/vars hash for readable per-tenant grouping.
    return "ai-cache:l1::" .. hex
end

return _M
