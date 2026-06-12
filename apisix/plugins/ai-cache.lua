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
local schema_mod   = require("apisix.plugins.ai-cache.schema")
local key_mod      = require("apisix.plugins.ai-cache.key")
local redis        = require("apisix.utils.redis")
local ngx          = ngx
local ngx_timer_at = ngx.timer.at
local pcall        = pcall

local plugin_name = "ai-cache"

-- Hardcoded in PR1; a follow-up makes these schema fields.
local STATUS_HEADER       = "X-AI-Cache-Status"
local MAX_CACHE_BODY_SIZE = 1048576   -- 1 MiB


local function release(cli, conf)
    local ok, err = cli:set_keepalive(conf.redis_keepalive_timeout,
                                      conf.redis_keepalive_pool)
    if not ok then
        core.log.warn("ai-cache: failed to set redis keepalive: ", err)
    end
end

local _M = {
    version        = 0.1,
    -- Just below ai-proxy (1040), ai-rate-limiting (1030) and
    -- ai-aliyun-content-moderation (1029): when this access phase runs,
    -- ai-proxy has already detected the protocol and stream mode, and a
    -- cache HIT is still subject to rate limiting and request moderation.
    priority       = 1028,
    name           = plugin_name,
    schema         = schema_mod.schema,
    encrypt_fields = schema_mod.encrypt_fields,
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.access(conf, ctx)
    -- ai-proxy's access (priority 1040) parses the body and publishes
    -- ctx.ai_client_protocol / ctx.var.request_type for lower-priority
    -- plugins. PR1 caches openai-chat only; everything else — including
    -- routes without ai-proxy at all — passes through unchanged.
    if ctx.ai_client_protocol ~= "openai-chat" then
        return
    end

    if ctx.var.request_type == "ai_stream" then
        -- Streaming responses are not cached in phase 1.
        core.response.set_header(STATUS_HEADER, "SKIP-STREAM")
        return
    end

    -- The key is derived from the request as received, so it cannot tell
    -- apart the per-instance model overrides an ai-proxy-multi route may
    -- apply. Until multi-instance semantics get their own follow-up, bypass
    -- caching on those routes. ctx.matched_route is the merged view, so this
    -- also covers ai-proxy-multi attached via a service or plugin_config.
    local route_plugins = ctx.matched_route and ctx.matched_route.value.plugins
    if route_plugins and route_plugins["ai-proxy-multi"] then
        return
    end

    -- Scope the key by the matched config identity and version: any
    -- route/service/plugin_config edit bumps ctx.conf_version, so entries
    -- cached under an older config (e.g. a different ai-proxy model
    -- override) can never be served after a change. Without a version there
    -- is no invalidation story, so do not cache at all.
    if ctx.conf_id == nil or ctx.conf_version == nil then
        return
    end

    local body = core.request.get_json_request_body_table()
    if not body then
        return
    end

    -- core.json.stably_encode raises on cjson.null (an explicit JSON null on
    -- any field); an uncaught error here would 5xx a request that ai-proxy
    -- could have served. Guard it and degrade to MISS.
    local ok, key = pcall(key_mod.build, body, {
        conf_id      = ctx.conf_id,
        conf_version = ctx.conf_version,
    })
    if not ok then
        core.log.warn("ai-cache: cache-key computation failed (treating as miss): ",
                      key)
        return
    end

    local cli, conn_err = redis.new(conf)
    if cli then
        local cached, get_err = cli:get(key)
        if get_err then
            core.log.warn("ai-cache: redis GET failed: ", get_err)
        elseif cached and cached ~= ngx.null then
            local _, decode_err = core.json.decode(cached, { null_as_nil = true })
            if decode_err then
                -- Corrupt cached entry: drop it best-effort and treat the
                -- request as a miss so the client gets a fresh upstream
                -- answer instead of garbage.
                core.log.warn("ai-cache: corrupt cached JSON (", decode_err,
                              "); deleting key and treating as miss")
                cli:del(key)
            else
                release(cli, conf)
                core.response.set_header(STATUS_HEADER, "HIT")
                core.response.set_header("Content-Type", "application/json")
                return 200, cached
            end
        end
        release(cli, conf)
    else
        core.log.warn("ai-cache: redis connect failed (treating as miss): ",
                      conn_err)
    end

    ctx.ai_cache = { key = key }
    core.response.set_header(STATUS_HEADER, "MISS")
end


-- ai-providers/base.lua hands every plugin's lua_body_filter the complete
-- upstream response body for non-streaming requests (per-SSE-chunk for
-- streams, which never reach here: access marks non-stream requests only).
-- A higher-priority plugin (e.g. a response moderation plugin) may have
-- rewritten the body before us, so what we stash — and later cache — is
-- exactly what the client receives.
function _M.lua_body_filter(conf, ctx, headers, body)
    local entry = ctx.ai_cache
    if not entry then
        return
    end
    entry.body = body
end


-- Background writer scheduled by _M.log. log_by_lua can't open cosockets,
-- so the Redis write runs in a timer (same pattern as limit-conn-redis).
local function write_to_cache(premature, conf, key, ttl, body)
    if premature then
        return
    end
    local cli, err = redis.new(conf)
    if not cli then
        core.log.warn("ai-cache: redis connect failed: ", err)
        return
    end
    local ok, set_err = cli:setex(key, ttl, body)
    if not ok then
        core.log.warn("ai-cache: redis SETEX failed: ", set_err)
    end
    release(cli, conf)
end


function _M.log(conf, ctx)
    local entry = ctx.ai_cache
    if not (entry and entry.key and entry.body) then
        return
    end
    if ngx.status < 200 or ngx.status >= 300 then
        return
    end
    local body = entry.body
    local _, decode_err = core.json.decode(body, { null_as_nil = true })
    if decode_err then
        core.log.debug("ai-cache: upstream body not JSON (", decode_err,
                       "); skipping cache write")
        return
    end
    if #body > MAX_CACHE_BODY_SIZE then
        core.log.debug("ai-cache: upstream body ", #body,
                       " bytes exceeds cap ", MAX_CACHE_BODY_SIZE,
                       "; skipping cache write")
        return
    end

    local ok, err = ngx_timer_at(0, write_to_cache, conf, entry.key,
                                  conf.exact.ttl, body)
    if not ok then
        core.log.warn("ai-cache: failed to schedule cache write: ", err)
    end
end


return _M
