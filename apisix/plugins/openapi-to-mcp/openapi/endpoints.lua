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
local pairs      = pairs
local ipairs     = ipairs
local type       = type
local tostring   = tostring
local math_huge  = math.huge
local table_sort = table.sort

local _M = {}

-- Order of openapi-types' OpenAPIV3.HttpMethods enum. extractToolsFromApi
-- iterates Object.values(OpenAPIV3.HttpMethods), so tools come out in this
-- order per path. Do not "fix" this to CRUD order.
local METHOD_ORDER = {
    "get", "put", "post", "delete", "options", "head", "patch", "trace",
}

local METHOD_RANK = {}
for rank, method in ipairs(METHOD_ORDER) do
    METHOD_RANK[method] = rank
end


local function param_key(param)
    return tostring(param["in"]) .. "\0" .. tostring(param.name)
end


-- Parameters declared on a Path Item apply to every operation under it; an
-- operation parameter with the same name and location overrides the inherited
-- one. See https://spec.openapis.org/oas/v3.0.3#path-item-object
-- The operation's own parameters come first, in their order, followed by the
-- inherited ones it does not override.
local function with_path_parameters(operation, path_params)
    if type(path_params) ~= "table" or #path_params == 0 then
        return operation
    end

    local merged = {}
    local declared = {}
    if type(operation.parameters) == "table" then
        for _, param in ipairs(operation.parameters) do
            merged[#merged + 1] = param
            if type(param) == "table" then
                declared[param_key(param)] = true
            end
        end
    end

    local inherited = false
    for _, param in ipairs(path_params) do
        if type(param) == "table" and not declared[param_key(param)] then
            merged[#merged + 1] = param
            inherited = true
        end
    end
    if not inherited then
        return operation
    end

    local copy = {}
    for key, value in pairs(operation) do
        copy[key] = value
    end
    copy.parameters = merged
    return copy
end


function _M.extract(spec, path_order)
    local out = {}
    if type(spec) ~= "table" or type(spec.paths) ~= "table" then
        return out
    end
    path_order = path_order or {}

    for path, path_item in pairs(spec.paths) do
        if type(path_item) == "table" then
            for _, method in ipairs(METHOD_ORDER) do
                local operation = path_item[method]
                if type(operation) == "table" then
                    out[#out + 1] = {
                        method = method,
                        path = path,
                        operation = with_path_parameters(operation, path_item.parameters),
                        _path_rank = path_order[path] or math_huge,
                        _method_rank = METHOD_RANK[method],
                    }
                end
            end
        end
    end

    table_sort(out, function(a, b)
        if a._path_rank ~= b._path_rank then
            return a._path_rank < b._path_rank
        end
        -- deterministic fallback when path_order has no entry for either path
        if a.path ~= b.path then
            return a.path < b.path
        end
        return a._method_rank < b._method_rank
    end)

    for _, e in ipairs(out) do
        e._path_rank = nil
        e._method_rank = nil
    end

    return out
end


return _M
