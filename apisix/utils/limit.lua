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

-- Connection credentials and tuning do not identify the counter's storage.
-- Keep this list shared by the three plugins instead of ignoring redis_*.
local backend_paths = {
    redis = "$['redis_host','redis_port','redis_database']",
    ["redis-cluster"] = "$['redis_cluster_name','redis_cluster_nodes']",
    ["redis-sentinel"] = "$['redis_sentinels','redis_master_name','redis_database','redis_role']",
}


local function project(conf, paths)
    local result = {}
    for _, path in ipairs(paths) do
        local parsed = parsed_paths[path]
        if not parsed then
            local err
            parsed, err = jsonpath.parse(path)
            if not parsed then
                return nil, err
            end
            parsed_paths[path] = parsed
        end

        local nodes, err = jsonpath.nodes(conf, parsed)
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


function _M.prepare_bucket_id(conf, fields)
    local identity, err = project(conf, fields)
    if not identity then
        return false, err
    end

    local policy = conf.policy or "local"
    local backend = {policy = policy}
    if backend_paths[policy] then
        backend, err = project(conf, {backend_paths[policy]})
        if not backend then
            return false, err
        end
        backend.policy = policy
        if backend.redis_cluster_nodes then
            core.table.sort(backend.redis_cluster_nodes)
        end
        if backend.redis_sentinels then
            core.table.sort(backend.redis_sentinels, function(a, b)
                return a.host .. ":" .. a.port < b.host .. ":" .. b.port
            end)
        end
    end
    identity.backend = backend

    -- A fresh encoder state keeps failures from affecting later checks.
    local data
    data, err = core.json.stably_encode(identity, {sortkey = true, exception = encode_null})
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
