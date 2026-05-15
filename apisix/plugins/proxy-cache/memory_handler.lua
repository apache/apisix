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

local memory_strategy = require("apisix.plugins.proxy-cache.memory").new
local util = require("apisix.plugins.proxy-cache.util")
local core = require("apisix.core")
local tab_new = require("table.new")
local ngx_re_gmatch = ngx.re.gmatch
local ngx_re_match = ngx.re.match
local parse_http_time = ngx.parse_http_time
local concat = table.concat
local sort = table.sort
local lower = string.lower
local floor = math.floor
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local ngx = ngx
local md5 = ngx.md5
local type = type
local pairs = pairs
local time = ngx.now
local max = math.max

-- Bumped from 1 to 2 when secondary-key (Vary) support was added. Entries
-- written by older code lack the variant layout, so they are purged on read
-- via the version-mismatch path.
local CACHE_VERSION = 2
local VARY_INDEX_SUFFIX = "::__vary"


-- Parse the upstream Vary header into a canonical list.
-- Returns:
--   nil           when the value contains `*` anywhere (RFC 9111 §4.1: not
--                 reusable; caller must refuse to cache).
--   empty table   when the header is absent/empty/whitespace-only.
--   sorted list   of lowercased, trimmed header names, otherwise. Sorting
--                 makes the variant signature independent of the order in
--                 which the upstream lists vary headers.
local function parse_vary_list(vary_value)
    if not vary_value or vary_value == "" then
        return {}
    end

    local result = {}
    local iter, iter_err = ngx_re_gmatch(vary_value, "([^,]+)", "oj")
    if not iter then
        core.log.error("failed to parse Vary header: ", iter_err)
        return {}
    end

    for token, _ in iter do
        local h = token[0]
        h = h:gsub("^%s+", ""):gsub("%s+$", "")
        if h == "*" then
            return nil
        end
        if h ~= "" then
            result[#result + 1] = lower(h)
        end
    end

    sort(result)
    return result
end


-- Hash the request's values for each header in `vary_headers` into a stable
-- per-variant signature. nginx normalizes header names to lowercase with
-- dashes converted to underscores for the `$http_*` variable family, so we
-- mirror that mapping. Missing headers contribute an empty string so the
-- same request always produces the same signature on store and lookup.
local function compute_signature(vary_headers, ctx)
    if not vary_headers or #vary_headers == 0 then
        return ""
    end

    local values = tab_new(#vary_headers, 0)
    for i, h in ipairs(vary_headers) do
        local var_name = "http_" .. h:gsub("-", "_")
        values[i] = ctx.var[var_name] or ""
    end
    return md5(concat(values, "\0"))
end


local function vary_lists_equal(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end


-- Purge every variant entry referenced by the index, then the index itself,
-- and finally the legacy base-key entry (which may exist if the URL ever
-- cached a no-Vary response in the past).
local function purge_all_variants(memory, base_key)
    local index_key = base_key .. VARY_INDEX_SUFFIX
    local index = memory:get(index_key)
    if index and type(index) == "table" and type(index.variants) == "table" then
        for _, sig in ipairs(index.variants) do
            memory:purge(base_key .. "::" .. sig)
        end
    end
    memory:purge(index_key)
    memory:purge(base_key)
end


-- Read-modify-write the variant index. If the existing index uses a
-- different vary header set than this response, we cannot reuse its
-- variants (their signatures were computed over different headers), so we
-- purge them and start fresh. Concurrent writers on the same base key may
-- race; the loser's variant becomes invisible to PURGE but stays reachable
-- by lookup until its own TTL expires.
local function update_vary_index(memory, base_key, vary_headers, signature, ttl)
    local index_key = base_key .. VARY_INDEX_SUFFIX
    local current = memory:get(index_key)

    local variants
    if current and type(current) == "table"
            and current.version == CACHE_VERSION
            and type(current.vary) == "table"
            and type(current.variants) == "table"
            and vary_lists_equal(current.vary, vary_headers) then
        variants = current.variants
        local found = false
        for _, s in ipairs(variants) do
            if s == signature then
                found = true
                break
            end
        end
        if not found then
            variants[#variants + 1] = signature
        end
    else
        if current and type(current) == "table" and type(current.variants) == "table" then
            for _, sig in ipairs(current.variants) do
                memory:purge(base_key .. "::" .. sig)
            end
        end
        variants = {signature}
    end

    local ok, err = memory:set(index_key, {
        vary     = vary_headers,
        variants = variants,
        version  = CACHE_VERSION,
    }, ttl)
    if not ok then
        core.log.error("failed to update vary index for ", base_key, ", err: ", err)
    end
end


-- Determine the storage key for the current request. If a valid index
-- exists for the base key, this request must look up the variant whose
-- signature matches the request's values for the indexed headers. Index
-- decode failures (malformed bytes, version mismatch, missing fields) all
-- fall through to the base key, which then misses and refetches.
local function lookup_storage_key(memory, base_key, ctx)
    local index = memory:get(base_key .. VARY_INDEX_SUFFIX)
    if not index or type(index) ~= "table" then
        return base_key
    end
    if index.version ~= CACHE_VERSION or type(index.vary) ~= "table" then
        return base_key
    end
    if #index.vary == 0 then
        return base_key
    end
    return base_key .. "::" .. compute_signature(index.vary, ctx)
end


local _M = {}

-- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
-- note content-length & apisix-cache-status are not strictly
-- hop-by-hop but we will be adjusting it here anyhow
local hop_by_hop_headers = {
    ["connection"]          = true,
    ["keep-alive"]          = true,
    ["proxy-authenticate"]  = true,
    ["proxy-authorization"] = true,
    ["te"]                  = true,
    ["trailers"]            = true,
    ["transfer-encoding"]   = true,
    ["upgrade"]             = true,
    ["content-length"]      = true,
    ["apisix-cache-status"] = true,
}


local function include_cache_header(header)
    local n_header = lower(header)
    if n_header == "expires" or n_header == "cache-control" then
        return true
    end

    return false
end


local function overwritable_header(header)
    local n_header = lower(header)

    return not hop_by_hop_headers[n_header]
            and not ngx_re_match(n_header, "ratelimit-remaining")
end


-- The following format can accept:
--      Cache-Control: no-cache
--      Cache-Control: no-store
--      Cache-Control: max-age=3600
--      Cache-Control: max-stale=3600
--      Cache-Control: min-fresh=3600
--      Cache-Control: private, max-age=600
--      Cache-Control: public, max-age=31536000
-- Refer to: https://www.holisticseo.digital/pagespeed/cache-control/
local function parse_directive_header(h)
    if not h then
        return {}
    end

    if type(h) == "table" then
        h = concat(h, ", ")
    end

    local t    = {}
    local res  = tab_new(3, 0)
    local iter = ngx_re_gmatch(h, "([^,]+)", "oj")

    local m = iter()
    while m do
        local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]],
            "oj", nil, res)
        if err then
            core.log.error(err)
        end

        -- store the directive token as a numeric value if it looks like a number;
        -- otherwise, store the string value. for directives without token, we just
        -- set the key to true
        t[lower(res[1])] = tonumber(res[2]) or res[2] or true

        m = iter()
    end

    return t
end


local function parse_resource_ttl(ctx, cc)
    local max_age = cc["s-maxage"] or cc["max-age"]

    if not max_age then
        local expires = ctx.var.upstream_http_expires

        -- if multiple Expires headers are present, last one wins
        if type(expires) == "table" then
            expires = expires[#expires]
        end

        local exp_time = parse_http_time(tostring(expires))
        if exp_time then
            max_age = exp_time - time()
        end
    end

    return max_age and max(max_age, 0) or 0
end


local function cacheable_request(conf, ctx, cc)
    if not util.match_method(conf, ctx) then
        return false, "MISS"
    end

    if conf.cache_bypass ~= nil then
        local value = util.generate_complex_value(conf.cache_bypass, ctx)
        core.log.info("proxy-cache cache bypass value:", value)
        if value ~= nil and value ~= "" and value ~= "0" then
            return false, "BYPASS"
        end
    end

    if conf.cache_control and (cc["no-store"] or cc["no-cache"]) then
        return false, "BYPASS"
    end

    return true, ""
end


local function cacheable_response(conf, ctx, cc)
    if not util.match_status(conf, ctx) then
        return false
    end

    if conf.no_cache ~= nil then
        local value = util.generate_complex_value(conf.no_cache, ctx)
        core.log.info("proxy-cache no-cache value:", value)

        if value ~= nil and value ~= "" and value ~= "0" then
            return false
        end
    end

    -- Always honor upstream Cache-Control directives that mark the response as
    -- non-shared/non-storable, regardless of the conf.cache_control flag. The
    -- flag governs request-side semantics; upstream response directives are a
    -- safety contract the application uses to mark personalized content.
    if cc["private"] or cc["no-store"] or cc["no-cache"] then
        return false
    end

    if conf.cache_control and parse_resource_ttl(ctx, cc) <= 0 then
        return false
    end

    -- Set-Cookie is per-recipient and not safe for a shared cache to store by
    -- default; require explicit opt-in via cache_set_cookie.
    if not conf.cache_set_cookie then
        local set_cookie = ctx.var.upstream_http_set_cookie
        if set_cookie and set_cookie ~= "" then
            return false
        end
    end

    -- Vary: * (RFC 9111 §4.1) means the response is not reusable; refuse to
    -- cache. parse_vary_list returns nil for that case.
    if ctx.var.upstream_http_vary then
        local vary_headers = parse_vary_list(ctx.var.upstream_http_vary)
        if vary_headers == nil then
            return false
        end
    end

    return true
end


function _M.access(conf, ctx)
    local cc = parse_directive_header(ctx.var.http_cache_control)

    if ctx.var.request_method ~= "PURGE" then
        local ret, msg = cacheable_request(conf, ctx, cc)
        if not ret then
            core.response.set_header("Apisix-Cache-Status", msg)
            return
        end
    end

    if not ctx.cache then
        ctx.cache = {
            memory = memory_strategy({shdict_name = conf.cache_zone}),
            hit = false,
            ttl = 0,
        }
    end

    local base_key = ctx.var.upstream_cache_key

    if ctx.var.request_method == "PURGE" then
        -- A URL with Vary support has no base-key entry, only variants
        -- under an index. Treat any of those as a purgeable hit.
        local base_res = ctx.cache.memory:get(base_key)
        local index = ctx.cache.memory:get(base_key .. VARY_INDEX_SUFFIX)
        if not base_res and not index then
            return 404
        end
        purge_all_variants(ctx.cache.memory, base_key)
        ctx.cache = nil
        return 200
    end

    local storage_key = lookup_storage_key(ctx.cache.memory, base_key, ctx)
    local res, err = ctx.cache.memory:get(storage_key)

    if err then
        if err == "expired" then
            core.response.set_header("Apisix-Cache-Status", "EXPIRED")

        elseif err ~= "not found" then
            core.response.set_header("Apisix-Cache-Status", "MISS")
            core.log.error("failed to get from cache, err: ", err)

        elseif conf.cache_control and cc["only-if-cached"] then
            core.response.set_header("Apisix-Cache-Status", "MISS")
            return 504

        else
            core.response.set_header("Apisix-Cache-Status", "MISS")
        end
        return
    end

    if res.version ~= CACHE_VERSION then
        core.log.warn("cache format mismatch, purging ", base_key)
        core.response.set_header("Apisix-Cache-Status", "BYPASS")
        purge_all_variants(ctx.cache.memory, base_key)
        return
    end

    if conf.cache_control then
        if cc["max-age"] and time() - res.timestamp > cc["max-age"] then
            core.response.set_header("Apisix-Cache-Status", "STALE")
            return
        end

        if cc["max-stale"] and time() - res.timestamp - res.ttl > cc["max-stale"] then
            core.response.set_header("Apisix-Cache-Status", "STALE")
            return
        end

        if cc["min-fresh"] and res.ttl - (time() - res.timestamp) < cc["min-fresh"] then
            core.response.set_header("Apisix-Cache-Status", "STALE")
            return
        end
    else
        if time() - res.timestamp > res.ttl then
            core.response.set_header("Apisix-Cache-Status", "STALE")
            return
        end
    end

    ctx.cache.hit = true

    for key, value in pairs(res.headers) do
        if conf.hide_cache_headers == true and include_cache_header(key) then
            core.response.set_header(key, "")
        elseif overwritable_header(key) then
            core.response.set_header(key, value)
        end
    end

    core.response.set_header("Age", floor(time() - res.timestamp))
    core.response.set_header("Apisix-Cache-Status", "HIT")

    return res.status, res.body
end


function _M.header_filter(conf, ctx)
    local cache = ctx.cache
    if not cache or cache.hit then
        return
    end

    local res_headers = ngx.resp.get_headers(0, true)

    for key in pairs(res_headers) do
        if conf.hide_cache_headers == true and include_cache_header(key) then
            core.response.set_header(key, "")
        end
    end

    local cc = parse_directive_header(ctx.var.upstream_http_cache_control)

    if cacheable_response(conf, ctx, cc) then
        cache.res_headers = res_headers
        cache.ttl = conf.cache_control and parse_resource_ttl(ctx, cc) or conf.cache_ttl
    else
        ctx.cache = nil
    end
end


function _M.body_filter(conf, ctx)
    local cache = ctx.cache
    if not cache or cache.hit then
        return
    end

    local res_body = core.response.hold_body_chunk(ctx, true)
    if not res_body then
        return
    end

    local entry = {
        status    = ngx.status,
        body      = res_body,
        body_len  = #res_body,
        headers   = cache.res_headers,
        ttl       = cache.ttl,
        timestamp = time(),
        version   = CACHE_VERSION,
    }

    local base_key = ctx.var.upstream_cache_key
    -- cacheable_response has already filtered out Vary: *, so parse_vary_list
    -- returns either an empty list (no vary) or the sorted header list.
    local vary_headers = parse_vary_list(ctx.var.upstream_http_vary) or {}
    local storage_key

    if #vary_headers > 0 then
        local signature = compute_signature(vary_headers, ctx)
        storage_key = base_key .. "::" .. signature
        update_vary_index(cache.memory, base_key, vary_headers, signature, cache.ttl)
        -- Drop any pre-Vary entry stored directly at the base key so future
        -- lookups never bypass the variant logic.
        cache.memory:purge(base_key)
    else
        -- This response has no Vary, but the URL may have cached a Vary
        -- response earlier; flush the prior index and its variants to
        -- prevent stale cross-variant matches.
        local prior = cache.memory:get(base_key .. VARY_INDEX_SUFFIX)
        if prior then
            purge_all_variants(cache.memory, base_key)
        end
        storage_key = base_key
    end

    local ok, err = cache.memory:set(storage_key, entry, cache.ttl)
    if not ok then
        core.log.error("failed to set cache, err: ", err)
    end
end


return _M
