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
local ffi  = require("ffi")
local ffi_new = ffi.new
local ffi_str = ffi.string
local tonumber = tonumber
local ipairs = ipairs
local type = type

local _M = {}

local ensured = {}


-- Memo keyed by Redis target (host#port#db) + index, not index alone: the same
-- index name against different Redis servers must be created on each.
local function memo_key(target, index)
    return target .. "|" .. index
end


-- little-endian FLOAT32 blob (RediSearch VECTOR PARAMS / HSET value)
function _M.pack_float32(vec)
    local n = #vec
    local buf = ffi_new("float[?]", n)
    for i = 1, n do
        buf[i - 1] = vec[i]
    end
    return ffi_str(buf, n * 4)
end


function _M.ensure_index(red, target, index, prefix, dim)
    local mk = memo_key(target, index)
    if ensured[mk] then
        return true
    end
    local ok, err = red[ "FT.CREATE" ](red, index,
        "ON", "HASH", "PREFIX", 1, prefix,
        "SCHEMA",
        "partition", "TAG",
        "embedding", "VECTOR", "HNSW", 6,
        "TYPE", "FLOAT32", "DIM", dim, "DISTANCE_METRIC", "COSINE")
    if not ok then
        -- FT.CREATE on an existing index returns this error; treat as success.
        if err and err:find("Index already exists", 1, true) then
            ensured[mk] = true
            return true
        end
        return nil, err
    end
    ensured[mk] = true
    return true
end


function _M.upsert(red, doc_key, fields, ttl)
    red:init_pipeline()
    red[ "HSET" ](red, doc_key,
        "partition", fields.partition,
        "embedding", fields.embedding,
        "response", fields.response,
        "created_at", fields.created_at,
        "format", fields.format)
    red:expire(doc_key, ttl)
    local res, err = red:commit_pipeline()
    if not res then
        return nil, err
    end
    for _, reply in ipairs(res) do
        if type(reply) == "table" and reply[1] == false then
            return nil, reply[2]
        end
    end
    return true
end


-- Returns the nearest hit { distance, response, created_at, format } or nil (no
-- err) on an empty result set.
function _M.knn_search(red, target, index, partition, vec, top_k)
    local query = "(@partition:{" .. partition .. "})=>[KNN " .. top_k ..
                  " @embedding $vec AS __score]"
    local res, err = red[ "FT.SEARCH" ](red, index, query,
        "PARAMS", 2, "vec", _M.pack_float32(vec),
        "RETURN", 4, "__score", "response", "created_at", "format",
        "SORTBY", "__score",
        "DIALECT", 2)
    if not res then
        -- self-heal: clear the memo on error so the next call re-runs FT.CREATE.
        ensured[memo_key(target, index)] = nil
        return nil, err
    end
    -- RESP: { total, docKey1, {f, v, f, v, ...}, docKey2, {...}, ... }
    if type(res) ~= "table" or (tonumber(res[1]) or 0) < 1 then
        return nil
    end
    local fields = res[3]
    if type(fields) ~= "table" then
        return nil
    end
    local hit = {}
    for i = 1, #fields, 2 do
        local k, v = fields[i], fields[i + 1]
        if k == "__score" then
            hit.distance = tonumber(v)
        elseif k == "response" then
            hit.response = v
        elseif k == "created_at" then
            hit.created_at = tonumber(v)
        elseif k == "format" then
            hit.format = v
        end
    end
    if not hit.response or not hit.distance then
        return nil
    end
    return hit
end


return _M
