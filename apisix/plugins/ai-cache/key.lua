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
local tostring     = tostring
local math         = math

local _M = {}

local U32_MAX = 4294967295

-- Collapse a non-negative float to an integer in milli-units, so float-parse
-- noise (0.2 vs 0.2000001) doesn't shatter the cache. NaN and negatives map
-- to 0; infinity and overflow saturate to U32_MAX. Only safe for fields whose
-- valid domain is non-negative (temperature, top_p) — signed fields such as
-- presence_penalty must NOT use this (negatives would all collide onto 0).
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

-- Only `stream` is excluded from the key: streaming requests are gated out
-- before any key is built, so stream true/false/absent must collapse to one
-- entry. EVERY other body field — including caller bookkeeping like `user` —
-- is hashed, so any output-affecting field (current or future) scopes the key
-- and can never silently cross-cache; the worst case of hashing too much is
-- an extra miss, never a wrong hit.
local NON_KEYED_FIELDS = {
    stream = true,
}

local function fingerprint(req, scope)
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
        body         = body,
        conf_id      = scope and scope.conf_id ~= nil
                       and tostring(scope.conf_id) or nil,
        conf_version = scope and scope.conf_version ~= nil
                       and tostring(scope.conf_version) or nil,
    }
end

-- _M.build(req, scope) -> "ai-cache:l1::<sha256hex>"
--   req   : parsed request body table, exactly as received from the client
--   scope : optional { conf_id = ..., conf_version = ... } — the matched
--           route/service/plugin_config identity and version (ctx.conf_id /
--           ctx.conf_version). Any config edit — including an in-place
--           ai-proxy model-override change — bumps conf_version, so entries
--           cached under an older config are unreachable afterwards.
--
-- The body is canonicalised by core.json.stably_encode (recursive object
-- key-sort; array order preserved, since message/tool order is semantic) and
-- hashed with SHA-256: a collision would BE a mis-cache, so a 64-bit hash is
-- not enough. Note stably_encode raises on cjson.null — callers must pcall.
function _M.build(req, scope)
    local fp = fingerprint(req, scope)
    local canonical = core.json.stably_encode(fp)
    local sha = resty_sha256:new()
    sha:update(canonical)
    local hex = str.to_hex(sha:final())
    -- "ai-cache:l1:<scope>:<request>" — the scope segment stays empty in PR1
    -- (conf id/version are folded into the hash); a later phase may fill it
    -- with a consumer/vars hash for readable per-tenant grouping.
    return "ai-cache:l1::" .. hex
end

return _M
