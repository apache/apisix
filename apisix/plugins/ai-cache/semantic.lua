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

-- Semantic L2 reconstructs the prompt through the client protocol's
-- get_messages(): the last turn becomes the embedded query and the rest becomes
-- the partition context. That is only sound when get_messages() is a faithful,
-- lossless view of the prompt. Today only openai-chat qualifies -- it returns
-- body.messages verbatim -- whereas the other protocols drop all non-text
-- content (images, tool calls, structured input), so two distinct prompts could
-- canonicalise to the same messages and collide on one cache cell. L2 therefore
-- engages only for these protocols and bypasses (exact L1 still applies) for the
-- rest, rather than risk a cross-prompt false hit.
local SEMANTIC_PROTOCOLS = {
    ["openai-chat"] = true,
}


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


-- Indices (into `messages`) of the messages whose text is embedded: the last
-- `message_countback` messages surviving the role filters. Shared by
-- extract_embed_text (which embeds them) and context_messages (which excludes
-- them from the L2 partition) so the two can never disagree on the split.
local function embed_window(messages, match)
    local m = match or {}
    local kept = {}
    for i, msg in ipairs(messages) do
        local role = msg.role
        local skip = (role == "system" and m.ignore_system_prompts ~= false)
                  or (role == "assistant" and m.ignore_assistant_prompts ~= false)
                  or (role == "tool" and m.ignore_tool_prompts ~= false)
        if not skip then
            kept[#kept + 1] = i
        end
    end
    local countback = m.message_countback or 1
    local start = #kept - countback + 1
    if start < 1 then start = 1 end
    local window = {}
    for w = start, #kept do
        window[#window + 1] = kept[w]
    end
    return window
end


function _M.extract_embed_text(messages, match)
    local texts = {}
    for _, i in ipairs(embed_window(messages, match)) do
        local t = text_of(messages[i].content)
        if t ~= "" then
            texts[#texts + 1] = t
        end
    end
    return concat(texts, "\n")
end


-- The messages NOT in the embed window: response-determining context (system
-- prompts, prior turns, RAG documents) that the embedding ignores. The semantic
-- layer folds these into the L2 partition so a generic instruction over
-- different context never collides on another context's cached response.
function _M.context_messages(messages, match)
    local in_window = {}
    for _, i in ipairs(embed_window(messages, match)) do
        in_window[i] = true
    end
    local context = {}
    for i, msg in ipairs(messages) do
        if not in_window[i] then
            context[#context + 1] = msg
        end
    end
    return context
end


function _M.window_has_nontext(messages, match)
    for _, i in ipairs(embed_window(messages, match)) do
        local content = messages[i].content
        if type(content) == "table" then
            for _, block in ipairs(content) do
                if type(block) == "table" and block.type and block.type ~= "text" then
                    return true
                end
            end
        end
    end
    return false
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
    local endpoint = c.endpoint
    if provider == "openai" then
        endpoint = endpoint or drivers.openai.DEFAULT_ENDPOINT
    end
    local repr = provider .. "|" .. (c.model or "") .. "|" .. (endpoint or "")
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


-- host#port#db identity, folded into the FT.CREATE memo key so the same index
-- name against different Redis targets is created on each (see redis.lua).
local function redis_target(conf)
    return (conf.redis_host or "") .. "#" .. (conf.redis_port or 6379)
           .. "#" .. (conf.redis_database or 0)
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


-- Phase 1 of the L2 lookup: gates + embedding. Does no Redis work -- embed() is
-- an HTTP call the caller must not pin a pooled connection across. Returns the
-- query vector (stashing the write-back ctx fields) or nil to fail open as MISS.
function _M.embed_query(conf, ctx, body)
    -- Bypass L2 (exact L1 still applies) for protocols whose canonical message
    -- form cannot faithfully represent the prompt; never a cross-prompt hit.
    if not SEMANTIC_PROTOCOLS[ctx.ai_client_protocol or ""] then
        return nil
    end
    local sem      = conf.semantic
    local messages = key_mod.messages(ctx, body)
    -- Bypass L2 when an embedded message carries non-text content (images, etc.):
    -- it is absent from both the vector and the partition, so a same-text
    -- different-image prompt would otherwise collide on one L2 cell.
    if _M.window_has_nontext(messages, sem.match) then
        return nil
    end
    local text     = _M.extract_embed_text(messages, sem.match)
    if text == "" then
        return nil
    end

    local vec, err = embed(conf, text)
    if not vec then
        core.log.warn("ai-cache: embedding failed, fail-open as MISS: ", err)
        return nil
    end
    -- stash for the write-back in log() (only set when embedding succeeded).
    -- context = the response-determining messages the embedding ignores; folding
    -- them into the partition isolates this prompt from other contexts. nil for a
    -- plain single-turn prompt, which keeps the partition identical to before.
    local ctxmsgs  = _M.context_messages(messages, sem.match)
    local part_ctx = #ctxmsgs > 0 and ctxmsgs or nil
    ctx.ai_cache_embedding  = vec
    ctx.ai_cache_dim        = #vec
    ctx.ai_cache_partition  = key_mod.partition(conf, ctx, body, part_ctx)
    return vec
end


-- Phase 2 of the L2 lookup: vector search over a caller-owned connection
-- acquired AFTER embed_query() (so the pool isn't pinned across embedding).
-- Returns a hit {body, created_at, similarity} on a >=threshold match, else nil.
function _M.search(red, conf, ctx, vec)
    local sem    = conf.semantic
    local target = redis_target(conf)
    local index  = _M.index_name(conf, #vec)
    local ok, err = vs.ensure_index(red, target, index, l2_prefix(conf, #vec), #vec)
    if not ok then
        core.log.warn("ai-cache: ensure_index failed, fail-open as MISS: ", err)
        return nil
    end

    local hit
    hit, err = vs.knn_search(red, target, index, ctx.ai_cache_partition, vec,
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
    local target   = redis_target(conf)
    local index    = _M.index_name(conf, l2.dim)
    local prefix   = l2_prefix(conf, l2.dim)
    local ok, err  = vs.ensure_index(red, target, index, prefix, l2.dim)
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
