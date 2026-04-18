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

--- Deep-merge helper for ai-proxy request body overrides.
-- Semantics:
--   * Both sides are plain objects (string-keyed tables) -> recursive merge.
--   * Otherwise (scalar, array, type mismatch, cjson.empty_array/empty_object)
--     -> patch value replaces target value wholesale.
-- This matches RFC 7396 JSON Merge Patch minus null-deletion.

local core = require("apisix.core")
local pairs = pairs
local next = next
local type = type
local getmetatable = getmetatable

local _M = {}


-- Returns true when tbl is a plain object (string keys only) that we should
-- recurse into. Empty tables, arrays, and cjson sentinels are treated as
-- "replace wholesale" to avoid ambiguity.
local function is_plain_object(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local mt = getmetatable(tbl)
    if mt == core.json.array_mt then
        return false
    end
    local k = next(tbl)
    if k == nil then
        -- Empty table: ambiguous; treat as "not an object" so patch replaces it.
        return false
    end
    return type(k) == "string"
end


local function deep_merge(target, patch)
    if not is_plain_object(target) or not is_plain_object(patch) then
        return patch
    end
    for k, v in pairs(patch) do
        target[k] = deep_merge(target[k], v)
    end
    return target
end
_M.deep_merge = deep_merge


return _M
