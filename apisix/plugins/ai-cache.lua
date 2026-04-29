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
local schema    = require("apisix.plugins.ai-cache.schema")
local exact     = require("apisix.plugins.ai-cache.exact")
local semantic  = require("apisix.plugins.ai-cache.semantic")
local protocols = require("apisix.plugins.ai-protocols")
local http      = require("resty.http")
local ngx_time  = ngx.time
local ngx_now   = ngx.now
local tostring  = tostring
local table_concat = table.concat

local plugin_name = "ai-cache"

local _M = {
    version = 0.1,
    priority = 1065,
    name = plugin_name,
    schema = schema.schema
}


local function layer_enabled(conf, name)
    local layers = conf.layers or { "exact", "semantic" }
    for _, l in ipairs(layers) do
        if l == name then return true end
    end
    return false
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.schema, conf)
    if not ok then
        return false, err
    end

    if layer_enabled(conf, "semantic") then
        if not (conf.semantic and conf.semantic.embedding) then
            return false, "semantic layer requires semantic.embedding to be configured"
        end
    end

    core.utils.check_https({ "semantic.embedding.endpoint" }, conf, plugin_name)

    return true
end


function _M.access(conf, ctx)
    -- Check bypass_on conditions
    if conf.bypass_on then
        local req_headers = ngx.req.get_headers()
        for _, rule in ipairs(conf.bypass_on) do
            if req_headers[rule.header] == rule.equals then
                ctx.ai_cache_bypass = true
                ctx.ai_cache_status = "BYPASS"
                return
            end
        end
    end

    local body_tab, err = core.request.get_json_request_body_table()
    if not body_tab then
        core.log.warn("ai-cache: failed to read request body: ", err or "unknown error")
        ctx.ai_cache_status = "MISS"
        return
    end

    local protocol_name = protocols.detect(body_tab, ctx)
    if not protocol_name then
        core.log.warn("ai-cache: could not detect AI protocol, skipping cache")
        ctx.ai_cache_status = "MISS"
        return
    end

    local proto = protocols.get(protocol_name)
    local contents = proto.extract_request_content(body_tab)
    if not contents or #contents == 0 then
        ctx.ai_cache_status = "MISS"
        return
    end

    local prompt_text = table_concat(contents, " ")
    local scope_hash = exact.compute_scope_hash(conf, ctx)
    local prompt_hash, hash_err = exact.compute_prompt_hash(prompt_text)
    if not prompt_hash then
        core.log.warn("ai-cache: failed to compute prompt hash: ", hash_err)
        ctx.ai_cache_status = "MISS"
        return
    end

    local is_stream = body_tab.stream == true

    -- L1 exact lookup
    if layer_enabled(conf, "exact") then
        local cached_text, written_at, lookup_err = exact.get(conf, scope_hash, prompt_hash)
        if lookup_err then
            core.log.warn("ai-cache: L1 lookup error: ", lookup_err)
        elseif cached_text then
            core.log.info("ai-cache: L1 hit for key: ", prompt_hash)
            ctx.ai_cache_status = "HIT-L1"
            ctx.ai_cache_written_at = written_at
            if is_stream then
                core.response.set_header("Content-Type", "text/event-stream")
            else
                core.response.set_header("Content-Type", "application/json")
            end
            return core.response.exit(200, proto.build_deny_response({
                stream = is_stream,
                text = cached_text,
            }))
        end
    end

    -- L2 semantic lookup
    if layer_enabled(conf, "semantic") then
        local emb_conf = conf.semantic.embedding
        local emb_driver = require("apisix.plugins.ai-cache.embeddings." .. emb_conf.provider)
        local httpc = http.new()

        local t0 = ngx_now()
        local embedding, _, emb_err = emb_driver.get_embeddings(emb_conf, prompt_text, httpc, true)
        if not embedding then
            core.log.warn("ai-cache: embedding fetch failed (degrading to MISS): ", emb_err)
        else
            ctx.ai_cache_embedding_latency_ms = (ngx_now() - t0) * 1000
            ctx.ai_cache_embedding_provider = emb_conf.provider
            ctx.ai_cache_embedding = embedding

            local threshold = conf.semantic.similarity_threshold or 0.95
            local cached_text, similarity, search_err = semantic.search(
                conf, scope_hash, embedding, threshold
            )

            if search_err then
                core.log.warn("ai-cache: L2 search error (degrading to MISS): ", search_err)
            elseif cached_text then
                core.log.info("ai-cache: L2 hit, similarity=", similarity)

                local l1_ttl = (conf.exact and conf.exact.ttl) or 3600
                local l1_err = exact.set(conf, scope_hash, prompt_hash, cached_text, l1_ttl)

                if l1_err then
                    core.log.warn("ai-cache: L2->L1 backfill failed: ", l1_err)
                end

                ctx.ai_cache_status = "HIT-L2"
                ctx.ai_cache_similarity = similarity
                if is_stream then
                    core.response.set_header("Content-Type", "text/event-stream")
                else
                    core.response.set_header("Content-Type", "application/json")
                end
                return core.response.exit(200, proto.build_deny_response({
                    stream = is_stream,
                    text = cached_text,
                }))
            end
        end
    end

    ctx.ai_cache_status = "MISS"
    ctx.ai_cache_scope_hash  = scope_hash
    ctx.ai_cache_prompt_hash = prompt_hash
    ctx.ai_cache_prompt_text = prompt_text
end


function _M.header_filter(conf, ctx)
    if not ctx.ai_cache_status then
        return
    end

    local status_header = (conf.headers and conf.headers.cache_status)
                            or "X-AI-Cache-Status"
    ngx.header[status_header] = ctx.ai_cache_status

    if ctx.ai_cache_status == "HIT-L1" and ctx.ai_cache_written_at then
        local age_header = (conf.headers and conf.headers.cache_age)
                            or "X-AI-Cache-Age"
        ngx.header[age_header] = tostring(ngx_time() - ctx.ai_cache_written_at)
    end

    if ctx.ai_cache_status == "HIT-L2" and ctx.ai_cache_similarity then
        local sim_header = (conf.headers and conf.headers.cache_similarity)
                            or "X-AI-Cache-Similarity"
        ngx.header[sim_header] = tostring(ctx.ai_cache_similarity)
    end
end


function _M.log(conf, ctx)
    if ctx.ai_cache_status ~= "MISS" then
        return
    end

    local upstream_status = core.response.get_upstream_status(ctx) or ngx.status
    if not upstream_status or upstream_status < 200 or upstream_status >= 300 then
        return
    end

    local response_text = ctx.var.llm_response_text
    if not response_text or response_text == "" then
        return
    end

    local exact_enabled = layer_enabled(conf, "exact")
    local semantic_enabled = layer_enabled(conf, "semantic")
    local ttl_exact = (conf.exact and conf.exact.ttl) or 3600
    local scope_hash = ctx.ai_cache_scope_hash
    local prompt_hash = ctx.ai_cache_prompt_hash
    local embedding = ctx.ai_cache_embedding
    local prompt_text = ctx.ai_cache_prompt_text

    ngx.timer.at(0, function(premature)
        if premature then
            return
        end
    
        if exact_enabled then
            local err = exact.set(conf, scope_hash, prompt_hash, response_text, ttl_exact)
            if err then
                ngx.log(ngx.ERR, "ai-cache: failed to write L1 cache: ", err)
            end
        end

        if semantic_enabled then
            local vec = embedding

            if not vec then
                local emb_conf = conf.semantic.embedding
                local emb_driver = require(
                    "apisix.plugins.ai-cache.embeddings." .. emb_conf.provider
                )
                local httpc = http.new()
                local emb, _, emb_err = emb_driver.get_embeddings(
                    emb_conf, prompt_text, httpc, true
                )
                if not emb then
                    ngx.log(ngx.WARN,
                        "ai-cache: failed to get embedding for L2 store: ", emb_err)
                    return
                end
                vec = emb
            end

            local ttl_semantic = (conf.semantic and conf.semantic.ttl) or 86400
            local store_err = semantic.store(
                conf, scope_hash, vec, response_text, ttl_semantic
            )
            if store_err then
                ngx.log(ngx.WARN, "ai-cache: failed to write L2 cache: ", store_err)
            end
        end
    end)
end


return _M
