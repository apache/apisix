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

local table_concat  = table.concat
local ngx_time      = ngx.time
local tostring      = tostring

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

    -- Read and parse request body
    local body_tab, err = core.request.get_json_request_body_table()
    if not body_tab then
        core.log.warn("ai-cache: failed to read request body: ", err or "unknown error")
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    local messages = body_tab.messages
    if not messages then
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    -- Compute cache key components
    local scope_hash = exact.compute_scope_hash(conf, ctx)
    local prompt_hash, err = exact.compute_prompt_hash(messages)
    if not prompt_hash then
        core.log.warn("ai-cache: failed to compute prompt hash: ", err)
        ctx.ai_cache_miss   = true
        ctx.ai_cache_status = "MISS"
        return
    end

    -- L1 exact lookup
    local layers = conf.layers or { "exact", "semantic" }
    local exact_enabled = false
    for _, l in ipairs(layers) do
        if l == "exact" then
            exact_enabled = true
            break
        end
    end

    if exact_enabled then
        local cached_body, written_at, lookup_err = exact.get(conf, scope_hash, prompt_hash)
        if lookup_err then
            core.log.warn("ai-cache: L1 lookup error: ", lookup_err)
        elseif cached_body then
            core.log.info("ai-cache: L1 hit for key ", prompt_hash)
            ctx.ai_cache_status     = "HIT-L1"
            ctx.ai_cache_written_at = written_at
            return core.response.exit(200, cached_body)
        end
    end

    -- MISS - store context for body_filter and log phases
    ctx.ai_cache_miss        = true
    ctx.ai_cache_status      = "MISS"
    ctx.ai_cache_scope_hash  = scope_hash
    ctx.ai_cache_prompt_hash = prompt_hash
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


function _M.body_filter(conf, ctx)
    if not ctx.ai_cache_miss then
        return
    end

    local chunk = ngx.arg[1]

    if type(chunk) == "string" and chunk ~= "" then
        if not ctx.ai_cache_body_chunks then
            ctx.ai_cache_body_chunks = {}
        end
        local chunks = ctx.ai_cache_body_chunks
        chunks[#chunks + 1] = chunk
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

    if not ctx.ai_cache_body_chunks then
        return
    end

    local body = table_concat(ctx.ai_cache_body_chunks)
    local max_size = conf.max_cache_body_size or 1048576
    if #body > max_size then
        core.log.warn("ai-cache: response body exceeds max_cache_body_size, skipping write")
        return
    end

    local ttl          = (conf.exact and conf.exact.ttl) or 3600
    local scope_hash   = ctx.ai_cache_scope_hash
    local prompt_hash  = ctx.ai_cache_prompt_hash

    ngx.timer.at(0, function(premature)
        if premature then return end
        local err = exact.set(conf, scope_hash, prompt_hash, body, ttl)
        if err then
            ngx.log(ngx.ERR, "ai-cache: failed to write L1 cache: ", err)
        end
    end)
end


return _M