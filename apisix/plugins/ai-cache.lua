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
local protocols = require("apisix.plugins.ai-protocols")
local ngx_time  = ngx.time
local tostring  = tostring
local table_concat = table.concat

local plugin_name = "ai-cache"

local _M = {
    version = 0.1,
    priority = 1065,
    name = plugin_name,
    schema = schema.schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.schema, conf)
    if not ok then
        return false, err
    end

    local layers = conf.layers or { "exact", "semantic" }
    for _, layer in ipairs(layers) do
        if layer == "semantic" and not (conf.semantic and conf.semantic.embedding) then
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
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    local protocol_name = protocols.detect(body_tab, ctx)
    if not protocol_name then
        core.log.warn("ai-cache: could not detect AI protocol, skipping cache")
        ctx.ai_cache_miss = true
        ctx.ai_cache_status = "MISS"
        return
    end

    local proto = protocols.get(protocol_name)
    local contents = proto.extract_request_content(body_tab)
    if not contents or #contents == 0 then
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    local prompt_text = table_concat(contents, " ")
    local scope_hash = exact.compute_scope_hash(conf, ctx)
    local prompt_hash, hash_err = exact.compute_prompt_hash(prompt_text)
    if not prompt_hash then
        core.log.warn("ai-cache: failed to compute prompt hash: ", hash_err)
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    local layers = conf.layers or { "exact", "semantic" }
    local exact_enabled = false
    for _, l in ipairs(layers) do
        if l == "exact" then
            exact_enabled = true
            break
        end
    end

    if exact_enabled then
        local cached_text, written_at, lookup_err = exact.get(conf, scope_hash, prompt_hash)
        if lookup_err then
            core.log.warn("ai-cache: L1 lookup error: ", lookup_err)
        elseif cached_text then
            core.log.info("ai-cache: L1 hit for key ", prompt_hash)
            ctx.ai_cache_status = "HIT-L1"
            ctx.ai_cache_written_at = written_at
            local is_stream = body_tab.stream == true
            return core.response.exit(200, proto.build_deny_response({
                stream = is_stream,
                text = cached_text,
            }))
        end
    end

    ctx.ai_cache_miss   = true
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
end


function _M.log(conf, ctx)
    if not ctx.ai_cache_miss or ctx.ai_cache_bypass then
        return
    end

    local status = core.response.get_upstream_status(ctx) or ngx.status
    if not status or status < 200 or status >= 300 then
        return
    end

    local response_text = ctx.var.llm_response_text
    if not response_text or response_text == "" then
        return
    end

    local ttl = (conf.exact and conf.exact.ttl) or 3600
    local scope_hash = ctx.ai_cache_scope_hash
    local prompt_hash = ctx.ai_cache_prompt_hash

    ngx.timer.at(0, function(premature)
        if premature then
            return
        end
    
        local err = exact.set(conf, scope_hash, prompt_hash, response_text, ttl)
        if err then
            ngx.log(ngx.ERR, "ai-cache: failed to write L1 cache: ", err)
        end
    end)
end


return _M