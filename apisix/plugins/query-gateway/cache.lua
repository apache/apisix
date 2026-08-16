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
local core = require("apisix.core")
local redis = require("apisix.utils.redis")
local rediscluster = require("apisix.utils.rediscluster")
local resty_sha256 = require("resty.sha256")
local to_hex = require("resty.string").to_hex
local ngx = ngx

local concat = table.concat
local lower = string.lower
local pairs = pairs
local ipairs = ipairs
local math_min = math.min
local math_max = math.max
local table_sort = table.sort
local tonumber = tonumber
local type = type

local _M = {}

local HOP_BY_HOP = {
    connection = true,
    ["keep-alive"] = true,
    ["proxy-authenticate"] = true,
    ["proxy-authorization"] = true,
    te = true,
    trailer = true,
    ["transfer-encoding"] = true,
    upgrade = true,
}

local ALLOWED_VARY = {
    accept = true,
    ["accept-encoding"] = true,
    ["accept-language"] = true,
}

local CACHE_REQUEST_HEADERS = {
    "cookie",
    "content-type",
    "content-encoding",
    "content-language",
    "content-length",
    "accept",
    "accept-encoding",
    "accept-language",
    "authorization",
    "range",
    "cache-control",
    "pragma",
    "if-match",
    "if-none-match",
    "if-modified-since",
    "if-unmodified-since",
}

local missing_shared_dict_logged = false

local function sha256_hex(value)
    local sha256 = resty_sha256:new()
    sha256:update(value)
    return to_hex(sha256:final())
end

local function shared_dict()
    local dict = ngx.shared["query-gateway-cache"]
    if not dict and not missing_shared_dict_logged then
        missing_shared_dict_logged = true
        core.log.warn("query-gateway-cache shared dict is unavailable; bypassing cache")
    end
    return dict
end

local function cache_id(conf)
    if conf.backend == "redis" then
        return "redis:" .. conf.redis_host .. ":" .. (conf.redis_port or 6379) .. ":" ..
               (conf.redis_database or 0)
    end

    if conf.backend == "redis-cluster" then
        return "redis-cluster:" .. conf.redis_cluster_name
    end

    return "local"
end

local function local_key(key)
    return "entry:" .. key
end

local function breaker_key(conf)
    return "breaker:" .. cache_id(conf)
end

local function write_queue_key(conf)
    return "write-queue:" .. sha256_hex(cache_id(conf))
end

local function write_timer_key(conf)
    return "write-timer:" .. sha256_hex(cache_id(conf))
end

local function use_fallback(conf, dict)
    if conf.backend == "local" then
        return true
    end

    return dict:get(breaker_key(conf)) ~= nil
end

local function mark_backend_failure(conf, dict, err)
    dict:set(breaker_key(conf), true, conf.fallback_ttl)
    core.log.warn("query-gateway cache backend unavailable: ", err,
                  "; using local memory for ", conf.fallback_ttl, " seconds")
end

local function local_get(dict, key)
    return dict:get(local_key(key))
end

local function local_set(dict, key, value, ttl)
    local ok, err = dict:set(local_key(key), value, ttl)
    if not ok then
        core.log.warn("failed to store query cache entry locally: ", err)
    end
    return ok
end

local function redis_get(conf, key)
    local red, err = redis.new(conf)
    if not red then
        return nil, err
    end

    local value
    value, err = red:get(key)
    local ok, keepalive_err = red:set_keepalive(conf.redis_keepalive_timeout or 10000,
                                                 conf.redis_keepalive_pool or 100)
    if not ok then
        core.log.warn("failed to set redis keepalive: ", keepalive_err)
    end

    if value == ngx.null then
        return nil
    end
    return value, err
end

local function redis_set(conf, key, value, ttl)
    local red, err = redis.new(conf)
    if not red then
        return nil, err
    end

    local ok
    ok, err = red:set(key, value, "EX", ttl)
    local keepalive_ok, keepalive_err = red:set_keepalive(conf.redis_keepalive_timeout or 10000,
                                                           conf.redis_keepalive_pool or 100)
    if not keepalive_ok then
        core.log.warn("failed to set redis keepalive: ", keepalive_err)
    end
    return ok, err
end

local function cluster_get(conf, key)
    local red, err = rediscluster.new(conf, "query-gateway-redis-cluster-slot-lock")
    if not red then
        return nil, err
    end

    local value
    value, err = red:get(key)
    if value == ngx.null then
        return nil
    end
    return value, err
end

local function cluster_set(conf, key, value, ttl)
    local red, err = rediscluster.new(conf, "query-gateway-redis-cluster-slot-lock")
    if not red then
        return nil, err
    end

    return red:set(key, value, "EX", ttl)
end

local function backend_get(conf, key)
    local dict = shared_dict()
    if not dict then
        return nil, "cache shared dict unavailable", "disabled"
    end

    if use_fallback(conf, dict) then
        return local_get(dict, key), nil, "local-fallback"
    end

    if conf.backend == "local" then
        return local_get(dict, key), nil, "local"
    end

    local value, err
    if conf.backend == "redis" then
        value, err = redis_get(conf, key)
    else
        value, err = cluster_get(conf, key)
    end

    if err then
        mark_backend_failure(conf, dict, err)
        return local_get(dict, key), nil, "local-fallback"
    end

    return value, nil, conf.backend
end

local function backend_set(conf, dict, key, value, ttl)
    if use_fallback(conf, dict) then
        return local_set(dict, key, value, conf.fallback_ttl)
    end

    if conf.backend == "local" then
        return local_set(dict, key, value, ttl)
    end

    local ok, err
    if conf.backend == "redis" then
        ok, err = redis_set(conf, key, value, ttl)
    else
        ok, err = cluster_set(conf, key, value, ttl)
    end

    if not ok then
        mark_backend_failure(conf, dict, err)
        return local_set(dict, key, value, conf.fallback_ttl)
    end

    return true
end

local function has_directive(value, directive)
    return value and ngx.re.find(lower(value), "(?:^|,)\\s*" .. directive .. "(?:\\s|,|=|$)", "jo")
end

local function trim(value)
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function has_repeated_cache_header(headers)
    for _, name in ipairs(CACHE_REQUEST_HEADERS) do
        if type(headers[name]) == "table" then
            return true
        end
    end
    return false
end

local function parse_cookie(header, allowed)
    local result = {}
    local seen = {}
    for pair in header:gmatch("[^;]+") do
        local name, value = pair:match("^%s*([^=]+)%s*=%s*(.*)%s*$")
        if name then
            name = trim(name)
        end
        if not name or not allowed[name] then
            return nil
        end
        seen[name] = value
    end

    for name, _ in pairs(allowed) do
        result[#result + 1] = name .. "=" .. (seen[name] or "")
    end
    table_sort(result)
    return concat(result, ";")
end

local function request_is_cacheable(conf, headers)
    if has_repeated_cache_header(headers) then
        return nil, "repeated cache header"
    end

    if headers["authorization"] or headers["range"] then
        return nil, "sensitive request header"
    end

    if headers["if-match"] or headers["if-none-match"] or headers["if-modified-since"] or
       headers["if-unmodified-since"] then
        return nil, "conditional request"
    end

    local request_cache_control = headers["cache-control"]
    if has_directive(request_cache_control, "no-store") or
       has_directive(request_cache_control, "no-cache") or
       headers["pragma"] and lower(headers["pragma"]):find("no-cache", 1, true) then
        return nil, "request cache directive"
    end

    if not headers["content-type"] or headers["content-type"] == "" then
        return nil, "missing content-type"
    end

    local cookie = headers["cookie"]
    local cookie_key = ""
    if cookie and cookie ~= "" then
        if not conf.cookie_names or #conf.cookie_names == 0 then
            return nil, "cookie request"
        end

        local allowed = {}
        for _, name in ipairs(conf.cookie_names) do
            allowed[name] = true
        end
        cookie_key = parse_cookie(cookie, allowed)
        if not cookie_key then
            return nil, "unallowlisted cookie"
        end
    end

    local content_length = tonumber(headers["content-length"])
    if content_length and content_length > conf.max_request_body_size then
        return nil, "request body exceeds cache limit"
    end

    return cookie_key
end

function _M.fetch(conf, ctx)
    local headers = core.request.headers(ctx)
    ctx.query_gateway_request_uri = ctx.query_gateway_request_uri or ctx.var.request_uri
    local cookie_key, reason = request_is_cacheable(conf, headers)
    if not cookie_key then
        return nil, reason
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        return nil, "request body is not held in memory"
    end

    if #body > conf.max_request_body_size then
        return nil, "request body exceeds cache limit"
    end

    local identity = ctx.consumer_name or ctx.var.remote_user or ""
    local key_material = concat({
        "v1",
        ctx.query_gateway_cache_method or "QUERY",
        ctx.route_id or ctx.conf_id or "",
        ctx.var.scheme or "",
        ctx.var.host or "",
        ctx.query_gateway_request_uri or "",
        headers["content-type"] or "",
        headers["content-encoding"] or "",
        headers["content-language"] or "",
        headers["accept"] or "",
        headers["accept-encoding"] or "",
        headers["accept-language"] or "",
        cookie_key,
        identity,
        sha256_hex(body),
    }, "\0")
    local key = "apisix:query-gateway:{" .. sha256_hex(key_material) .. "}"

    local value, _, backend = backend_get(conf, key)
    ctx.query_gateway_cache_key = key
    ctx.query_gateway_cache_backend = backend
    if not value then
        return nil, "miss"
    end

    local entry, err = core.json.decode(value)
    if not entry then
        core.log.warn("invalid query cache entry: ", err)
        return nil, "invalid entry"
    end

    return entry, "hit"
end

function _M.serve(entry)
    ngx.status = entry.status
    for name, value in pairs(entry.headers) do
        ngx.header[name] = value
    end
    local stored_at = entry.stored_at or ngx.time()
    local age = math_max(entry.age or 0, ngx.time() - stored_at)
    ngx.header["Age"] = age
    ngx.header["Apisix-Cache-Status"] = "HIT"
    ngx.print(ngx.decode_base64(entry.body))
    return ngx.exit(entry.status)
end

local function response_is_cacheable(conf, ctx, headers)
    if type(headers["cache-control"]) == "table" or type(headers["vary"]) == "table" or
       type(headers["age"]) == "table" then
        return nil
    end

    if ngx.status ~= 200 or headers["set-cookie"] or headers["www-authenticate"] or
       headers["proxy-authenticate"] or headers["content-range"] then
        return nil
    end

    local cache_control = headers["cache-control"]
    if has_directive(cache_control, "private") or has_directive(cache_control, "no-store") or
       has_directive(cache_control, "no-cache") or has_directive(cache_control, "max-age=0") or
       has_directive(cache_control, "s-maxage=0") then
        return nil
    end

    local vary = headers["vary"]
    if vary and vary ~= "" then
        for item in vary:gmatch("[^,]+") do
            item = lower(item:gsub("^%s+", ""):gsub("%s+$", ""))
            if not ALLOWED_VARY[item] then
                return nil
            end
        end
    end

    local ttl = conf.ttl
    local max_age = cache_control and
                    ngx.re.match(cache_control, "(?:s-maxage|max-age)=(\\d+)", "ijo")
    if max_age then
        ttl = math_min(ttl, tonumber(max_age[1]))
    end
    if ttl <= 0 then
        return nil
    end

    return ttl
end

function _M.header_filter(conf, ctx)
    if ctx.query_gateway_cache_hit or not ctx.query_gateway_cache_key then
        return
    end

    local headers = ngx.resp.get_headers()
    local ttl = response_is_cacheable(conf, ctx, headers)
    if not ttl then
        ctx.query_gateway_cache_key = nil
        return
    end

    local stored_headers = {}
    for name, value in pairs(headers) do
        if not HOP_BY_HOP[lower(name)] and lower(name) ~= "set-cookie" then
            stored_headers[name] = value
        end
    end

    ctx.query_gateway_cache_entry = {
        status = ngx.status,
        headers = stored_headers,
        chunks = {},
        size = 0,
        ttl = ttl,
        stored_at = ngx.time(),
        age = tonumber(headers["age"]) or 0,
    }
    ngx.header["Apisix-Cache-Status"] = "MISS"
end

function _M.body_filter(conf, ctx)
    if ctx.query_gateway_cache_hit then
        return
    end

    local entry = ctx.query_gateway_cache_entry
    if not entry then
        return
    end

    local chunk = ngx.arg[1]
    if chunk and #chunk > 0 then
        entry.size = entry.size + #chunk
        if entry.size > conf.max_response_body_size then
            ctx.query_gateway_cache_entry = nil
            return
        end
        entry.chunks[#entry.chunks + 1] = chunk
    end

    if not ngx.arg[2] then
        return
    end

    local payload = core.json.encode({
        status = entry.status,
        headers = entry.headers,
        body = ngx.encode_base64(concat(entry.chunks)),
        stored_at = entry.stored_at,
        age = entry.age,
    })
    local key, ttl = ctx.query_gateway_cache_key, entry.ttl
    local cache_conf = conf
    ctx.query_gateway_cache_entry = nil

    local dict = shared_dict()
    if not dict then
        return
    end

    if cache_conf.backend == "local" then
        backend_set(cache_conf, dict, key, payload, ttl)
        return
    end

    local queue_key = write_queue_key(cache_conf)
    local queue_length, queue_err = dict:llen(queue_key)
    if not queue_length then
        core.log.warn("failed to inspect query cache write queue: ", queue_err)
        return
    end

    local queue_size = cache_conf.write_queue_size or 1024
    if queue_length >= queue_size then
        core.log.warn("query cache write queue is full; dropping cache entry")
        return
    end

    local queued, queue_push_err = dict:lpush(queue_key, core.json.encode({
        key = key,
        payload = payload,
        ttl = ttl,
    }))
    if not queued then
        core.log.warn("failed to enqueue query cache entry: ", queue_push_err)
        return
    end

    local timer_key = write_timer_key(cache_conf)
    local timer_started = dict:add(timer_key, true, 60)
    if not timer_started then
        return
    end

    local function drain(premature)
        if premature then
            dict:delete(timer_key)
            return
        end

        local batch_size = cache_conf.write_batch_size or 32
        for _ = 1, batch_size do
            local item, pop_err = dict:rpop(queue_key)
            if pop_err then
                core.log.warn("failed to dequeue query cache entry: ", pop_err)
                break
            end
            if not item then
                break
            end

            local queued_entry, decode_err = core.json.decode(item)
            if not queued_entry then
                core.log.warn("failed to decode query cache entry: ", decode_err)
            else
                backend_set(cache_conf, dict, queued_entry.key, queued_entry.payload,
                            queued_entry.ttl)
            end
        end

        local remaining = dict:llen(queue_key) or 0
        if remaining > 0 then
            local ok, err = ngx.timer.at(0, drain)
            if ok then
                return
            end
            core.log.warn("failed to continue query cache write drain: ", err)
        end

        dict:delete(timer_key)
        if (dict:llen(queue_key) or 0) > 0 then
            local restarted = dict:add(timer_key, true, 60)
            if restarted then
                local ok, err = ngx.timer.at(0, drain)
                if not ok then
                    dict:delete(timer_key)
                    core.log.warn("failed to restart query cache write drain: ", err)
                end
            end
        end
    end

    local ok, err = ngx.timer.at(0, drain)
    if not ok then
        dict:delete(timer_key)
        core.log.warn("failed to start query cache write drain: ", err)
    end
end

return _M
