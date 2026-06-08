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
local base         = require("apisix.plugins.ai-proxy.base")
local key_mod      = require("apisix.plugins.ai-cache.key")
local redis        = require("apisix.utils.redis")
local rediscluster = require("apisix.utils.rediscluster")
local ngx          = ngx
local ngx_timer_at = ngx.timer.at

local plugin_name = "ai-cache"

-- Hardcoded in Phase 1a; Phase 1e makes these schema fields.
local STATUS_HEADER       = "X-AI-Cache-Status"
local MAX_CACHE_BODY_SIZE = 1048576   -- 1 MiB


local function get_client(conf)
    if conf.policy == "redis-cluster" then
        local cli, err = rediscluster.new(conf, "plugin-ai-cache-redis-cluster-slot-lock")
        return cli, err, "cluster"
    end
    local cli, err = redis.new(conf)
    return cli, err, "single"
end


local function release(cli, mode, conf)
    if mode == "cluster" then
        -- rediscluster keeps its own pool
        return
    end
    cli:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
end

local _M = {
    version        = 0.1,
    priority       = 1086,
    name           = plugin_name,
    schema         = schema_mod.schema,
    encrypt_fields = schema_mod.encrypt_fields,
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.access(conf, ctx)
    -- Use the idempotent detect_request_type so ai-proxy can reuse the result.
    local err = base.detect_request_type(ctx)
    if err then
        -- Non-JSON body, unsupported content-type, or no matching protocol —
        -- defer to ai-proxy which will handle/400 appropriately.
        core.log.debug("ai-cache: detect_request_type: ", err, "; deferring")
        return
    end

    -- PR1 caches openai-chat only; other protocols pass through unchanged.
    if ctx.ai_client_protocol ~= "openai-chat" then
        return
    end

    if ctx.var.request_type == "ai_stream" then
        -- Streaming responses are not cached in phase 1.
        core.response.set_header(STATUS_HEADER, "SKIP-STREAM")
        return
    end

    -- Mark as cache-eligible; the actual Redis lookup happens in before_proxy
    -- after ai-proxy.access has picked the instance and set ctx.picked_ai_instance.
    ctx.ai_cache_lookup = true
end


function _M.before_proxy(conf, ctx)
    if not ctx.ai_cache_lookup then
        return
    end

    -- Obtain the effective (post-instance-override) request body.
    local eff = base.effective_request_for_cache(ctx)
    if not eff then
        -- Fail-open: unable to compute effective body, let ai-proxy proxy.
        return
    end

    local instance_name = ctx.picked_ai_instance_name
        or (ctx.picked_ai_instance and ctx.picked_ai_instance.name)

    local key = key_mod.build(eff, {
        protocol = ctx.ai_client_protocol,
        instance = instance_name,
    })

    local cli, conn_err, mode = get_client(conf)
    if cli then
        local cached, get_err = cli:get(key)
        if get_err then
            core.log.warn("ai-cache: redis GET failed: ", get_err)
        elseif cached and cached ~= ngx.null then
            local _, decode_err = core.json.decode(cached, { null_as_nil = true })
            if decode_err then
                -- Corrupt cached entry: drop it best-effort and treat the
                -- request as a miss so the client gets a fresh upstream
                -- answer instead of garbage (RFC phase-1 § 2.6).
                core.log.warn("ai-cache: corrupt cached JSON (", decode_err,
                              "); deleting key and treating as miss")
                cli:del(key)
            else
                release(cli, mode, conf)
                core.response.set_header(STATUS_HEADER, "HIT")
                core.response.set_header("Content-Type", "application/json")
                return 200, cached
            end
        end
        release(cli, mode, conf)
    else
        core.log.warn("ai-cache: redis connect failed (treating as miss): ",
                      conn_err)
    end

    ctx.ai_cache = { key = key, started_at = ngx.now() }
    core.response.set_header(STATUS_HEADER, "MISS")
end


-- Background writer scheduled by _M.log. log_by_lua can't open cosockets,
-- so the Redis write runs in a timer (same pattern as limit-conn-redis).
local function write_to_cache(premature, conf, key, ttl, body)
    if premature then
        return
    end
    local cli, err, mode = get_client(conf)
    if not cli then
        core.log.warn("ai-cache: redis connect failed: ", err)
        return
    end
    local ok, set_err = cli:setex(key, ttl, body)
    if not ok then
        core.log.warn("ai-cache: redis SETEX failed: ", set_err)
    end
    release(cli, mode, conf)
end


function _M.log(conf, ctx)
    local entry = ctx.ai_cache
    if not (entry and entry.key) then
        return
    end
    if ngx.status < 200 or ngx.status >= 300 then
        return
    end
    local body = ctx.llm_raw_response_body
    if not body then
        core.log.debug("ai-cache: no llm_raw_response_body; skipping cache write")
        return
    end
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
