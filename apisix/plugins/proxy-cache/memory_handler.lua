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
local lower = string.lower
local floor = math.floor
local tostring = tostring
local tonumber = tonumber
local ngx = ngx
local type = type
local pairs = pairs
local time = ngx.now
local max = math.max

local CACHE_VERSION = 1

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

    if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"]) then
        return false
    end

    if conf.cache_control and parse_resource_ttl(ctx, cc) <= 0 then
        return false
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

    local res, err = ctx.cache.memory:get(ctx.var.upstream_cache_key)

    if ctx.var.request_method == "PURGE" then
        if err == "not found" then
            return 404
        end
        ctx.cache.memory:purge(ctx.var.upstream_cache_key)
        ctx.cache = nil
        return 200
    end

    if err then
        core.response.set_header("Apisix-Cache-Status", "MISS")
        if err ~= "not found" then
            core.log.error("failed to get from cache, err: ", err)
        elseif conf.cache_control and cc["only-if-cached"] then
            return 504
        end
        return
    end

    if res.version ~= CACHE_VERSION then
        core.log.warn("cache format mismatch, purging ", ctx.var.upstream_cache_key)
        core.response.set_header("Apisix-Cache-Status", "BYPASS")
        ctx.cache.memory:purge(ctx.var.upstream_cache_key)
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

    local res = {
        status    = ngx.status,
        body      = res_body,
        body_len  = #res_body,
        headers   = cache.res_headers,
        ttl       = cache.ttl,
        timestamp = time(),
        version   = CACHE_VERSION,
    }

    local res, err = cache.memory:set(ctx.var.upstream_cache_key, res, cache.ttl)
    if not res then
        core.log.error("failed to set cache, err: ", err)
    end
end


return _M
