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
local schema     = require("apisix.plugins.ai-cache.schema")
local key_mod    = require("apisix.plugins.ai-cache.key")
local binding    = require("apisix.plugins.ai-protocols.binding")
local redis_util = require("apisix.utils.redis")
local semantic   = require("apisix.plugins.ai-cache.semantic")
local stream     = require("apisix.plugins.ai-cache.stream")

local ngx        = ngx
local ngx_null   = ngx.null
local ipairs     = ipairs
local pcall      = pcall
local concat     = table.concat
local str_format = string.format

local CACHE_STATUS_HEADER     = "X-AI-Cache-Status"
local CACHE_AGE_HEADER        = "X-AI-Cache-Age"
local CACHE_SIMILARITY_HEADER = "X-AI-Cache-Similarity"
local DEFAULT_TTL             = 3600
local DEFAULT_MAX_BODY        = 1048576
local DEFAULT_SEMANTIC_TTL    = 86400

local _M = {
    version  = 0.1,
    priority = 1035,
    name     = "ai-cache",
    schema   = schema,
}


local function has_layer(conf, name)
    local layers = conf.layers or { "exact" }
    for _, l in ipairs(layers) do
        if l == name then
            return true
        end
    end
    return false
end


function _M.check_schema(conf)
    core.utils.check_https({
        "semantic.embedding.openai.endpoint",
        "semantic.embedding.azure_openai.endpoint",
    }, conf, _M.name)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.semantic and not has_layer(conf, "semantic") then
        core.log.warn("ai-cache: 'semantic' is configured but not listed in ",
                      "'layers'; the semantic (L2) cache is inactive")
    end
    return true
end


local function release(conf, red)
    local ok, err = red:set_keepalive(conf.redis_keepalive_timeout or 10000,
                                      conf.redis_keepalive_pool or 100)
    if not ok then
        core.log.warn("ai-cache: failed to set redis keepalive: ", err)
    end
end


-- Run fn(red) on a pooled connection: released on success, closed when fn
-- returns an error or throws. Returns fn's result, or (nil, err) on any failure.
local function with_redis(conf, fn)
    local red, err = redis_util.new(conf)
    if not red then
        return nil, err
    end
    local ok, res, ferr = pcall(fn, red)
    if not ok or ferr then
        red:close()
        return nil, not ok and res or ferr
    end
    release(conf, red)
    return res
end


-- fail-open: a cache-backend or embedding failure must never break the
-- request; log it and treat the lookup as a MISS.
local function fail_open(ctx, what, err)
    core.log.warn("ai-cache: ", what, ", fail-open as MISS: ", err)
    ctx.ai_cache_status = "MISS"
end


-- The L1 stored value; encoded only here so the shape has one home.
local function encode_entry(body, created_at, format)
    return core.json.encode({ body = body, created_at = created_at, format = format })
end


-- Best-effort L2 -> L1 backfill under this request's L1 key, carrying
-- created_at and format so either layer replays the hit identically.
local function backfill_l1(conf, ctx, red, hit)
    local envelope = encode_entry(hit.body, hit.created_at, hit.format)
    if not envelope then
        core.log.warn("ai-cache: L1 backfill skipped: json.encode returned nil")
        return
    end
    local ok, err = red:set(ctx.ai_cache_key, envelope,
                            "EX", (conf.exact and conf.exact.ttl) or DEFAULT_TTL)
    if not ok then
        core.log.warn("ai-cache: L1 backfill SET failed: ", err)
    end
end


local function serve_hit(conf, ctx, cached, similarity)
    local status = "HIT"
    ctx.ai_cache_status = status
    ctx.ai_cache_hit_layer = similarity and "semantic" or "exact"
    if conf.cache_headers ~= false then
        core.response.set_header(CACHE_STATUS_HEADER, status)
        local age = ngx.time() - (cached.created_at or ngx.time())
        core.response.set_header(CACHE_AGE_HEADER, age < 0 and 0 or age)
        if similarity then
            core.response.set_header(CACHE_SIMILARITY_HEADER,
                                     str_format("%.4f", similarity))
        end
    end
    core.response.set_header("Content-Type",
        cached.format == stream.FORMAT_SSE and "text/event-stream"
                                            or "application/json")
    return core.response.exit(200, cached.body)
end


function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "no ai instance picked (request did not pass through ai-proxy/ai-proxy-multi)",
            500, "ai-cache must be used with the ai-proxy or ai-proxy-multi plugin")
        if handled then
            return code, body
        end
        ctx.ai_cache_status = "BYPASS"
        return
    end

    -- A stream on a non-SSE wire framing (bedrock's aws-eventstream) can never
    -- be captured or replayed, so the lookup would be a guaranteed-miss redis
    -- GET on every request: bypass before doing any work.
    if ctx.var.request_type == "ai_stream"
       and not stream.provider_capturable(ctx.picked_ai_instance) then
        ctx.ai_cache_status = "BYPASS"
        return
    end

    if conf.bypass_on then
        for _, rule in ipairs(conf.bypass_on) do
            if core.request.header(ctx, rule.header) == rule.equals then
                ctx.ai_cache_status = "BYPASS"
                return
            end
        end
    end

    local body, err = core.request.get_json_request_body_table()
    if not body then
        core.log.warn("ai-cache: cannot read request body, bypassing: ", err)
        ctx.ai_cache_status = "BYPASS"
        return
    end

    ctx.ai_cache_fingerprint = key_mod.fingerprint(ctx, body)
    ctx.ai_cache_key = key_mod.build(conf, ctx, ctx.ai_cache_fingerprint)
    -- which instance the fingerprint was computed for; log() checks it so a
    -- fallback instance's response is never written under this key
    ctx.ai_cache_picked_at_access = ctx.picked_ai_instance

    local cached
    cached, err = with_redis(conf, function(red)
        local res, gerr = red:get(ctx.ai_cache_key)
        if gerr then
            return nil, gerr
        end
        if res == nil or res == ngx_null then
            return nil
        end
        local entry = core.json.decode(res)
        if entry and entry.body then
            return entry
        end
        core.log.warn("ai-cache: discarding malformed cache entry for ", ctx.ai_cache_key)
        return nil
    end)
    if err then
        return fail_open(ctx, "L1 lookup failed", err)
    end
    if cached then
        return serve_hit(conf, ctx, cached)
    end

    -- L1 miss -> L2 semantic lookup, in its own connection scope so the pool
    -- isn't pinned across embed_query()'s HTTP round-trip.
    if has_layer(conf, "semantic") and conf.semantic then
        local ok, vec = pcall(semantic.embed_query, conf, ctx, body)
        if not ok then
            fail_open(ctx, "semantic embed error", vec)
            -- prevent log() from scheduling a write with partial/bad state
            ctx.ai_cache_embedding = nil
            return
        end

        if vec then
            local hit
            hit, err = with_redis(conf, function(red)
                local h = semantic.search(red, conf, ctx, vec)
                if h then
                    local bok, berr = pcall(backfill_l1, conf, ctx, red, h)
                    if not bok then
                        core.log.warn("ai-cache: L1 backfill error: ", berr)
                    end
                end
                return h
            end)
            if err then
                fail_open(ctx, "semantic search failed", err)
                ctx.ai_cache_embedding = nil
                return
            end
            if hit then
                return serve_hit(conf, ctx, hit, hit.similarity)
            end
        end
    end

    ctx.ai_cache_status = "MISS"
end


function _M.header_filter(conf, ctx)
    if ctx.ai_cache_status and conf.cache_headers ~= false then
        core.response.set_header(CACHE_STATUS_HEADER, ctx.ai_cache_status)
    end
end


function _M.body_filter(conf, ctx)
    -- only a MISS gets written back; HIT exited in access, BYPASS opts out.
    if ctx.ai_cache_status ~= "MISS" or ctx.ai_cache_oversized
       or not stream.capturable(ctx) then
        return
    end
    local chunk = ngx.arg[1]
    if chunk and #chunk > 0 then
        local buf = ctx.ai_cache_buf
        if not buf then
            buf = { n = 0, bytes = 0 }
            ctx.ai_cache_buf = buf
        end
        local n = buf.n + 1
        buf.n = n
        buf[n] = chunk
        buf.bytes = buf.bytes + #chunk
        if buf.bytes > (conf.max_cache_body_size or DEFAULT_MAX_BODY) then
            ctx.ai_cache_buf = nil
            ctx.ai_cache_oversized = true
        end
    end
end


-- body_filter/log cannot use cosockets, so the Redis write runs in a 0-delay
-- timer. l2 (optional) = { partition, embedding, dim, fingerprint, ttl }.
local function write_to_cache(premature, conf, cache_key, response_body, l2, format)
    if premature then
        return
    end
    local now = ngx.time()
    local envelope = encode_entry(response_body, now, format)
    local _, err = with_redis(conf, function(red)
        local ok, serr = red:set(cache_key, envelope, "EX",
                                 (conf.exact and conf.exact.ttl) or DEFAULT_TTL)
        if not ok then
            return nil, serr
        end
        if l2 then
            l2.created_at = now
            l2.format = format
            semantic.write(red, conf, l2, response_body)
        end
        return true
    end)
    if err then
        core.log.warn("ai-cache: cache write failed: ", err)
    end
end


function _M.log(conf, ctx)
    if ctx.ai_cache_status ~= "MISS" or not ctx.ai_cache_fingerprint then
        return
    end
    -- the fingerprint identifies the instance picked at access time; a
    -- fallback/retry response from another instance must not be cached under it
    if ctx.picked_ai_instance ~= ctx.ai_cache_picked_at_access then
        return
    end
    if ngx.status ~= 200 then
        return
    end
    if ctx.ai_stream_aborted then
        return
    end
    local buf = ctx.ai_cache_buf
    if not buf or buf.bytes == 0 then
        return
    end
    local response_body = concat(buf, "", 1, buf.n)

    local format = stream.capture_format(ctx, response_body)
    if not format then
        return
    end

    local cache_key = key_mod.build(conf, ctx, ctx.ai_cache_fingerprint)

    -- L2 doc from ctx fields stashed by semantic.embed_query(); the embedding
    -- is only set on a successful embed.
    local l2
    if has_layer(conf, "semantic") and ctx.ai_cache_embedding then
        l2 = {
            partition  = ctx.ai_cache_partition,
            embedding  = ctx.ai_cache_embedding,
            dim        = ctx.ai_cache_dim,
            fingerprint = ctx.ai_cache_fingerprint,
            ttl        = (conf.semantic and conf.semantic.ttl) or DEFAULT_SEMANTIC_TTL,
        }
    end

    local ok, err = ngx.timer.at(0, write_to_cache, conf, cache_key,
                                 response_body, l2, format)
    if not ok then
        core.log.warn("ai-cache: failed to schedule cache write: ", err)
    end
end


return _M
