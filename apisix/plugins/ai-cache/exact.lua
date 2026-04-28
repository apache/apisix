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
local redis        = require("apisix.utils.redis")
local resty_sha256 = require("resty.sha256")
local to_hex       = require("resty.string").to_hex

local table_concat  = table.concat
local table_sort    = table.sort
local ngx_time      = ngx.time
local tostring      = tostring

local KEY_PREFIX = "ai-cache:l1:"

local _M = {}


local function sha256_hex(s)
    local hash = resty_sha256:new()
    hash:update(s)
    return to_hex(hash:final())
end

_M.sha256_hex = sha256_hex

function _M.compute_scope_hash(conf, ctx)
    local cache_key = conf.cache_key
    if not cache_key then
        return ""
    end

    local parts = {}
    local n = 0

    if cache_key.include_consumer then
        n = n + 1
        parts[n] = ctx.consumer_name or ""
    end

    if cache_key.include_vars then
        for _, var_name in ipairs(cache_key.include_vars) do
            local key = var_name
            if key:sub(1, 1) == "$" then
                key = key:sub(2)
            end
            n = n + 1
            parts[n] = tostring(ctx.var[key] or "")
        end
    end

    if n == 0 then
        return ""
    end

    table_sort(parts)
    return sha256_hex(table_concat(parts, "|"))
end


function _M.compute_prompt_hash(text)
    return sha256_hex(text), nil
end


function _M.get(conf, scope_hash, prompt_hash)
    local red, err = redis.new(conf)
    if not red then
        return nil, nil, err
    end

    local key = KEY_PREFIX .. scope_hash .. ":" .. prompt_hash
    local res, err = red:get(key)
    red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)

    if err then
        return nil, nil, err
    end

    if res == ngx.null then
        return nil, nil, nil
    end

    local entry, decode_err = core.json.decode(res)
    if not entry then
        return nil, nil, "corrupt cache entry: " .. decode_err
    end

    return entry.text, entry.written_at, nil
end


function _M.set(conf, scope_hash, prompt_hash, text, ttl)
    local red, err = redis.new(conf)
    if not red then
        return err
    end

    local key = KEY_PREFIX .. scope_hash .. ":" .. prompt_hash
    local entry, encode_err = core.json.encode({
        text = text,
        written_at = ngx_time(),
    })

    if not entry then
        red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
        return encode_err
    end

    local ok, err = red:set(key, entry, "EX", ttl)
    red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)

    if not ok then
        return err
    end
    return nil
end


return _M
