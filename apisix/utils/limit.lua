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
local jsonpath = require("jsonpath")
local ipairs = ipairs
local type = type
local rawget = rawget
local getmetatable = getmetatable
local setmetatable = setmetatable
local tostring = tostring
local crc32 = ngx.crc32_long
local parsed_paths = {}

local _M = {}

local function select_nodes(conf, path)
    local parsed = parsed_paths[path]
    if not parsed then
        local err
        parsed, err = jsonpath.parse(path)
        if not parsed then
            return nil, err
        end
        parsed_paths[path] = parsed
    end
    return jsonpath.nodes(conf, parsed)
end


local function project(conf, paths)
    local result = {}
    for _, path in ipairs(paths) do
        local nodes, err = select_nodes(conf, path)
        if not nodes then
            return nil, err
        end
        for _, node in ipairs(nodes) do
            local parent = result
            for i = 2, #node.path do
                local key = node.path[i]
                if type(key) == "number" then
                    key = key + 1 -- JSONPath arrays are zero-based.
                end
                if i == #node.path then
                    parent[key] = core.table.deepcopy(node.value)
                else
                    parent[key] = parent[key] or {}
                    parent = parent[key]
                end
            end
        end
    end
    return result
end


local function encode_null(_, value, _, message)
    if value == core.json.null then
        return "null"
    end
    return nil, message
end


local function stable_encode(value)
    -- A fresh encoder state keeps failures from affecting later checks.
    return core.json.stably_encode(value, {sortkey = true, exception = encode_null})
end


function _M.prepare_bucket_id(conf, fields, unordered_fields)
    local identity, err = project(conf, fields)
    if not identity then
        return false, err
    end

    -- The caller owns field selection and declares which arrays are unordered.
    -- Normalize the projected copy without changing the input configuration.
    for _, path in ipairs(unordered_fields or {}) do
        local nodes
        nodes, err = select_nodes(identity, path)
        if not nodes then
            return false, err
        end
        for _, node in ipairs(nodes) do
            local encoded = {}
            for _, value in ipairs(node.value) do
                local data
                data, err = stable_encode(value)
                if not data then
                    return false, err
                end
                encoded[value] = data
            end
            core.table.sort(node.value, function(a, b)
                return encoded[a] < encoded[b]
            end)
        end
    end

    local data
    data, err = stable_encode(identity)
    if not data then
        return false, err
    end

    local meta = conf._meta or {}
    conf._meta = meta
    local mt = core.table.clone(getmetatable(meta) or {})
    local old_index = mt.__index
    mt.bucket_id = tostring(crc32(data))
    -- Runtime metadata stays outside JSON and survives configuration copies.
    -- Preserve existing metadata, including parent, and let set_plugins_meta_parent
    -- add parent to this metatable after configuration validation.
    mt.__index = function(t, key)
        local value = rawget(mt, key)
        if value ~= nil then
            return value
        end
        if type(old_index) == "table" then
            return old_index[key]
        elseif type(old_index) == "function" then
            return old_index(t, key)
        end
    end
    setmetatable(meta, mt)
    return true
end


function _M.get_bucket_id(conf)
    local mt = conf._meta and getmetatable(conf._meta)
    return mt and rawget(mt, "bucket_id")
end


return _M
