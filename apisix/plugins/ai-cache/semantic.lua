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

local apisix_redis = require("apisix.utils.redis")
local uuid = require("resty.jit-uuid")
local ffi = require("ffi")

local ffi_new = ffi.new
local ffi_string = ffi.string
local ngx_time = ngx.time
local tostring = tostring
local tonumber = tonumber
local type = type

local _M = {}


local function index_name(dim)
    return "ai-cache-idx-" .. dim
end


local function key_prefix(dim)
    return "ai-cache:l2:" .. dim .. ":"
end

local function pack_vector(vec)
    local n = #vec
    local buf = ffi_new("float[?]", n)
    for i = 0, n - 1 do
        buf[i] = vec[i + 1]
    end
    return ffi_string(buf, n * 4)
end

local index_ready = {}

local function ensure_index(red, dim)
    if index_ready[dim] then
        return true
    end

    local _, err = red["FT.CREATE"](red,
        index_name(dim),
        "ON", "HASH",
        "PREFIX", "1", key_prefix(dim),
        "SCHEMA",
        "embedding", "VECTOR", "HNSW", "6",
        "TYPE", "FLOAT32",
        "DIM", tostring(dim),
        "DISTANCE_METRIC", "COSINE",
        "scope", "TAG",
        "created_at", "NUMERIC"
    )

    if err and not err:find("already exists") then
        return nil, "FT.CREATE failed: " .. err
    end

    index_ready[dim] = true
    return true
end


function _M.search(conf, scope_hash, embedding_vec, threshold)
    local red, err = apisix_redis.new(conf)
    if not red then
        return nil, nil, err
    end

    local ok, init_err = ensure_index(red, #embedding_vec)
    if not ok then
        red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
        return nil, nil, init_err
    end

    local binary_vec = pack_vector(embedding_vec)

    local query
    if scope_hash == "" then
        query = "*=>[KNN 1 @embedding $vec AS dist]"
    else
        query = "@scope:{" .. scope_hash .. "} *=>[KNN 1 @embedding $vec AS dist]"
    end

    local res, search_err = red["FT.SEARCH"](red,
        index_name(#embedding_vec),
        query,
        "PARAMS", "2", "vec", binary_vec,
        "SORTBY", "dist", "ASC",
        "LIMIT", "0", "1",
        "RETURN", "2", "response", "dist",
        "DIALECT", "2"
    )
    red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)

    if search_err then
        return nil, nil, search_err
    end

    if not res or res[1] == 0 then
        return nil, nil, nil
    end

    -- RESP2: {count, key, {field, val, field, val, ...}, ...}
    local fields = res[3]
    if type(fields) ~= "table" then
        return nil, nil, nil
    end

    local response_text, dist
    for i = 1, #fields, 2 do
        if fields[i] == "response" then
            response_text = fields[i + 1]
        elseif fields[i] == "dist" then
            dist = tonumber(fields[i + 1])
        end
    end

    if not response_text or not dist then
        return nil, nil, nil
    end

    local similarity = 1 - dist
    if similarity < threshold then
        return nil, nil, nil
    end

    return response_text, similarity, nil
end


function _M.store(conf, scope_hash, embedding_vec, text, ttl)
    local red, err = apisix_redis.new(conf)
    if not red then
        return err
    end

    local ok, init_err = ensure_index(red, #embedding_vec)
    if not ok then
        red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
        return init_err
    end

    local binary_vec = pack_vector(embedding_vec)
    local key = key_prefix(#embedding_vec) .. uuid.generate_v4()

    local set_ok, set_err = red:hset(key,
        "embedding", binary_vec,
        "response", text,
        "scope", scope_hash,
        "created_at", tostring(ngx_time())
    )

    if not set_ok then
        red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
        return set_err
    end

    red:expire(key, ttl)
    red:set_keepalive(conf.redis_keepalive_timeout, conf.redis_keepalive_pool)
    return nil
end


return _M
