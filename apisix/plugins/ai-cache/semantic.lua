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
local core    = require("apisix.core")
local http    = require("resty.http")
local sha256  = require("resty.sha256")
local to_hex  = require("resty.string").to_hex
local key_mod = require("apisix.plugins.ai-cache.key")
local vs      = require("apisix.plugins.ai-cache.vector-search.redis")

local ipairs = ipairs
local type   = type
local concat = table.concat
local tostring = tostring

-- Pre-require both drivers so a misconfigured provider name cannot escape
-- lookup()'s fail-open boundary via a request-time require() raise.
local drivers = {
    openai       = require("apisix.plugins.ai-cache.embeddings.openai"),
    azure_openai = require("apisix.plugins.ai-cache.embeddings.azure_openai"),
}

local _M = {}

local DEFAULT_THRESHOLD = 0.95
local DEFAULT_TOP_K     = 1


local function text_of(content)
    if type(content) == "string" then
        return content
    end
    if type(content) == "table" then
        local parts = {}
        for _, block in ipairs(content) do
            if type(block) == "table" and block.type == "text" and block.text then
                parts[#parts + 1] = block.text
            end
        end
        return concat(parts, "\n")
    end
    return ""
end


function _M.extract_embed_text(messages, match)
    local m = match or {}
    local kept = {}
    for _, msg in ipairs(messages) do
        local role = msg.role
        local skip = (role == "system" and m.ignore_system_prompts ~= false)
                  or (role == "assistant" and m.ignore_assistant_prompts ~= false)
                  or (role == "tool" and m.ignore_tool_prompts ~= false)
        if not skip then
            kept[#kept + 1] = msg
        end
    end
    local countback = m.message_countback or 1
    local start = #kept - countback + 1
    if start < 1 then start = 1 end
    local texts = {}
    for i = start, #kept do
        local t = text_of(kept[i].content)
        if t ~= "" then
            texts[#texts + 1] = t
        end
    end
    return concat(texts, "\n")
end


-- Base name for this plugin instance's RediSearch index and L2 key prefix.
-- The schema requires vector_search and defaults redis.index to "ai-cache",
-- so the validated conf always carries the value.
local function l2_base(conf)
    return conf.semantic.vector_search.redis.index
end


-- Short, stable fingerprint of the EMBEDDING model space (provider + model +
-- endpoint + dimensions). Cosine distance is only meaningful between vectors
-- from the same model, so this is folded into the index name and key prefix:
-- changing the embedding model (even to one of the same dimensionality) lands
-- in a fresh, isolated index instead of being compared against stale vectors
-- from the previous model.
local function emb_identity(conf)
    local emb      = conf.semantic.embedding
    local provider = emb.openai and "openai" or "azure_openai"
    local c        = emb[provider]
    local repr = provider .. "|" .. (c.model or "") .. "|" .. (c.endpoint or "")
                 .. "|" .. tostring(c.dimensions or "")
    local h = sha256:new()
    h:update(repr)
    return to_hex(h:final()):sub(1, 16)
end


function _M.index_name(conf, dim)
    return l2_base(conf) .. ":idx:" .. emb_identity(conf) .. ":" .. dim
end


-- HASH key prefix the index is built over. Scoped by embedding identity AND
-- dimension so two indexes (different model or different dim) never share docs.
local function l2_prefix(conf, dim)
    return l2_base(conf) .. ":l2:" .. emb_identity(conf) .. ":" .. dim .. ":"
end


-- conf.semantic.embedding is a one-key sub-object {openai=..|azure_openai=..}
local function embed(conf, text)
    local emb      = conf.semantic.embedding
    local provider = emb.openai and "openai" or "azure_openai"
    local driver   = drivers[provider]
    local pconf    = emb[provider]
    local httpc    = http.new()
    -- Bound the synchronous embedding call so a slow/hung provider cannot stall
    -- the request for the resty default (~60s) before fail-open kicks in.
    local t = pconf.timeout or 5000
    httpc:set_timeouts(t, t, t)
    return driver.get_embeddings(pconf, text, httpc, pconf.ssl_verify ~= false)
end


-- Returns a hit {body, created_at, similarity} on a >=threshold match, else nil.
-- Fail-open: any error logs a warning and returns nil.
function _M.lookup(red, conf, ctx, body)
    local sem  = conf.semantic
    local text = _M.extract_embed_text(key_mod.messages(ctx, body), sem.match)
    if text == "" then
        return nil
    end

    local vec, err = embed(conf, text)
    if not vec then
        core.log.warn("ai-cache: embedding failed, fail-open as MISS: ", err)
        return nil
    end
    -- stash for the write-back in log() (only set when embedding succeeded)
    ctx.ai_cache_embedding  = vec
    ctx.ai_cache_dim        = #vec
    ctx.ai_cache_partition  = key_mod.partition(conf, ctx, body)

    local index = _M.index_name(conf, #vec)
    local ok
    ok, err = vs.ensure_index(red, index, l2_prefix(conf, #vec), #vec)
    if not ok then
        core.log.warn("ai-cache: ensure_index failed, fail-open as MISS: ", err)
        return nil
    end

    local hit
    hit, err = vs.knn_search(red, index, ctx.ai_cache_partition, vec,
                             sem.top_k or DEFAULT_TOP_K)
    if err then
        core.log.warn("ai-cache: knn search failed, fail-open as MISS: ", err)
        return nil
    end
    if not hit then
        return nil
    end

    local similarity = 1 - hit.distance
    if similarity < (sem.similarity_threshold or DEFAULT_THRESHOLD) then
        return nil
    end

    -- L2 -> L1 backfill, carrying the L2 entry's original created_at so Age is
    -- consistent whether the next hit is served from L1 or L2.  A real semantic
    -- hit must be served regardless — only the backfill SET is skipped on error.
    local envelope = core.json.encode({ body = hit.response, created_at = hit.created_at })
    if not envelope then
        core.log.warn("ai-cache: L1 backfill skipped: json.encode returned nil")
    else
        local exact_ttl = (conf.exact and conf.exact.ttl) or 3600
        local bok, berr = red:set(ctx.ai_cache_key, envelope, "EX", exact_ttl)
        if not bok then
            core.log.warn("ai-cache: L1 backfill SET failed: ", berr)
        end
    end

    return { body = hit.response, created_at = hit.created_at, similarity = similarity }
end


-- Called from the write-back timer (after the L1 SET) with a still-open `red`.
-- l2 = { partition, embedding, dim, fingerprint, ttl, created_at }
function _M.write(red, conf, l2, response_body)
    if not l2 or not l2.embedding then
        return
    end
    local index    = _M.index_name(conf, l2.dim)
    local prefix   = l2_prefix(conf, l2.dim)
    local ok, err  = vs.ensure_index(red, index, prefix, l2.dim)
    if not ok then
        core.log.warn("ai-cache: ensure_index on write failed: ", err)
        return
    end
    local doc_key = prefix .. l2.partition .. ":" .. l2.fingerprint
    ok, err = vs.upsert(red, doc_key, {
        partition  = l2.partition,
        embedding  = vs.pack_float32(l2.embedding),
        response   = response_body,
        created_at = l2.created_at,
    }, l2.ttl)
    if not ok then
        core.log.warn("ai-cache: L2 upsert failed: ", err)
    end
end


return _M
