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

local ngx        = ngx
local ngx_null   = ngx.null
local ipairs     = ipairs
local concat     = table.concat

local CACHE_STATUS_HEADER = "X-AI-Cache-Status"
local CACHE_AGE_HEADER    = "X-AI-Cache-Age"
local DEFAULT_TTL         = 3600
local DEFAULT_MAX_BODY    = 1048576

local _M = {
    version  = 0.1,
    priority = 1035,
    name     = "ai-cache",
    schema   = schema,
}


function _M.check_schema(conf)
    if conf.semantic and conf.semantic.embedding then
        local emb = conf.semantic.embedding
        if emb.openai and emb.openai.endpoint then
            core.utils.check_https({ "semantic.embedding.openai.endpoint" }, conf, _M.name)
        end
        if emb.azure_openai and emb.azure_openai.endpoint then
            core.utils.check_https({ "semantic.embedding.azure_openai.endpoint" }, conf, _M.name)
        end
    end
    return core.schema.check(schema, conf)
end


local function release(conf, red)
    local ok, err = red:set_keepalive(conf.redis_keepalive_timeout or 10000,
                                      conf.redis_keepalive_pool or 100)
    if not ok then
        core.log.warn("ai-cache: failed to set redis keepalive: ", err)
    end
end


local function serve_hit(conf, ctx, cached)
    ctx.ai_cache_status = "HIT"
    if conf.cache_headers ~= false then
        core.response.set_header(CACHE_STATUS_HEADER, "HIT")
        local age = ngx.time() - (cached.created_at or ngx.time())
        core.response.set_header(CACHE_AGE_HEADER, age < 0 and 0 or age)
    end
    core.response.set_header("Content-Type", "application/json")
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

    -- Streaming responses are not cached in PR-1 (SSE replay is a later
    -- increment). ai-proxy (higher priority) has already classified the
    -- request, so bypass before doing any work.
    if ctx.var.request_type == "ai_stream" then
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
    -- Remember which instance the fingerprint was computed for. ai-proxy-multi
    -- may fall back to a different instance in before_proxy; the log phase uses
    -- this to avoid writing that fallback response under the original key.
    ctx.ai_cache_picked_at_access = ctx.picked_ai_instance

    local red
    red, err = redis_util.new(conf)
    if not red then
        -- fail-open: never let a cache-backend outage break the request.
        core.log.warn("ai-cache: redis unavailable, fail-open as MISS: ", err)
        ctx.ai_cache_status = "MISS"
        return
    end

    local res
    res, err = red:get(ctx.ai_cache_key)
    if err then
        red:close()
        core.log.warn("ai-cache: redis get failed, fail-open as MISS: ", err)
        ctx.ai_cache_status = "MISS"
        return
    end
    release(conf, red)

    if res ~= nil and res ~= ngx_null then
        local cached = core.json.decode(res)
        if cached and cached.body then
            return serve_hit(conf, ctx, cached)
        end
        core.log.warn("ai-cache: discarding malformed cache entry for ", ctx.ai_cache_key)
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
    if ctx.ai_cache_status ~= "MISS" or ctx.ai_cache_oversized then
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


-- The response-capturing phases (body_filter / log) run in contexts where
-- cosockets are disabled, so the Redis write is deferred to a 0-delay timer
-- (timers run in a light thread where cosockets are allowed).
local function write_to_cache(premature, conf, cache_key, response_body)
    if premature then
        return
    end
    local red, err = redis_util.new(conf)
    if not red then
        core.log.warn("ai-cache: redis unavailable on write: ", err)
        return
    end
    local envelope = core.json.encode({ body = response_body, created_at = ngx.time() })
    local ttl = (conf.exact and conf.exact.ttl) or DEFAULT_TTL
    local ok
    ok, err = red:set(cache_key, envelope, "EX", ttl)
    if not ok then
        red:close()
        core.log.warn("ai-cache: redis set failed: ", err)
        return
    end
    release(conf, red)
end


function _M.log(conf, ctx)
    if ctx.ai_cache_status ~= "MISS" or not ctx.ai_cache_fingerprint then
        return
    end
    -- ai-proxy-multi may reassign the picked instance on fallback/retry during
    -- before_proxy. The frozen fingerprint identifies the ORIGINAL instance, so a
    -- response actually produced by a different (fallback) instance must not be
    -- written under it -- that would replay the wrong instance's response on a
    -- later hit.
    if ctx.picked_ai_instance ~= ctx.ai_cache_picked_at_access then
        return
    end
    if ngx.status ~= 200 then
        return
    end
    local buf = ctx.ai_cache_buf
    if not buf or buf.bytes == 0 then
        return
    end
    local response_body = concat(buf, "", 1, buf.n)

    local cache_key = key_mod.build(conf, ctx, ctx.ai_cache_fingerprint)
    local ok, err = ngx.timer.at(0, write_to_cache, conf, cache_key, response_body)
    if not ok then
        core.log.warn("ai-cache: failed to schedule cache write: ", err)
    end
end


return _M
