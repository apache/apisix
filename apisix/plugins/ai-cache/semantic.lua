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
local next   = next
local concat = table.concat
local tostring = tostring
local ngx_now = ngx.now

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
-- the partition context. That is only sound when get_messages() is a faithful
-- view of the prompt's TEXT. Today only openai-chat qualifies; other protocols
-- reshape or drop text, so two distinct prompts could canonicalise to the same
-- messages and collide on one cache cell. get_messages() also flattens away all
-- non-text content (images, tool calls), so non-text prompts are bypassed
-- separately via body_has_nontext() below. L2 therefore engages only for these
-- protocols (exact L1 still applies to the rest).
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


-- A content part that is present but not plain text (image, audio, tool result).
local function block_is_nontext(block)
    return type(block) == "table" and block.type ~= nil and block.type ~= "text"
end


local function is_nonempty_table(v)
    return type(v) == "table" and next(v) ~= nil
end


-- True when the RAW body carries prompt state get_messages() drops: a non-text
-- content block (image, audio, ...) or a tool/function call. That state is in
-- neither the vector nor the L2 partition, so a same-text prompt that differs
-- only there would otherwise collide on one L2 cell.
-- Tolerant of malformed input: non-table message items and content shaped as a
-- single block object (not an array) are handled, never indexed blindly.
function _M.body_has_nontext(body)
    local messages = type(body) == "table" and body.messages
    if type(messages) ~= "table" then
        return false
    end
    for _, msg in ipairs(messages) do
        if type(msg) == "table" then
            -- tool/function calls are response-determining prompt state
            if is_nonempty_table(msg.tool_calls)
               or is_nonempty_table(msg.function_call) then
                return true
            end
            local content = msg.content
            if type(content) == "table" then
                -- content may be an array of blocks or a single block object
                if block_is_nontext(content) then
                    return true
                end
                for _, block in ipairs(content) do
                    if block_is_nontext(block) then
                        return true
                    end
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
    -- Bypass L2 for prompts carrying non-text content (images, etc.): it lives in
    -- neither the vector nor the partition, so a same-text different-media prompt
    -- would otherwise collide on one L2 cell.
    if _M.body_has_nontext(body) then
        return nil
    end
    local sem      = conf.semantic
    local messages = key_mod.messages(ctx, body)
    local text     = _M.extract_embed_text(messages, sem.match)
    if text == "" then
        return nil
    end

    local started = ngx_now()
    local vec, err = embed(conf, text)
    ctx.ai_cache_embedding_latency = (ngx_now() - started) * 1000
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
-- Returns a hit {body, created_at, format, similarity} on a >=threshold match,
-- else nil. The L1 backfill of a hit is the caller's job (ai-cache.lua owns L1).
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

    return { body = hit.response, created_at = hit.created_at,
             format = hit.format, similarity = similarity }
end


-- Called from the write-back timer (after the L1 SET) with a still-open `red`.
-- l2 = { partition, embedding, dim, fingerprint, ttl, created_at, format }
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
        format     = l2.format,
    }, l2.ttl)
    if not ok then
        core.log.warn("ai-cache: L2 upsert failed: ", err)
    end
end


return _M
