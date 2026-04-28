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

--- Json schema validation module.
--
-- @module core.schema

local jsonschema = require('jsonschema')
local lrucache = require("apisix.core.lrucache")
local schema_def = require("apisix.schema_def")
local cached_validator = lrucache.new({count = 1000, ttl = 0})
local pcall = pcall
local require = require
local error = error
local type = type
local pairs = pairs
local ipairs = ipairs
local tab_insert = table.insert
local tab_remove = table.remove
local math_max = math.max

local _M = {
    version = 0.3,

    TYPE_CONSUMER = 1,
    TYPE_METADATA = 2,
}


local function create_validator(schema)
    -- local code = jsonschema.generate_validator_code(schema, opts)
    -- local file2=io.output("/tmp/2.txt")
    -- file2:write(code)
    -- file2:close()
    local ok, res = pcall(jsonschema.generate_validator, schema)
    if ok then
        return res
    end

    return nil, res -- error message
end

local function get_validator(schema)
    local validator, err = cached_validator(schema, nil,
                                create_validator, schema)

    if not validator then
        return nil, err
    end

    return validator, nil
end

local function strip_required(schema, removed)
    if schema.required then
        local new_req = {}
        for _, r in ipairs(schema.required) do
            local keep = true
            for _, rm in ipairs(removed) do
                if r == rm then keep = false; break end
            end
            if keep then
                tab_insert(new_req, r)
            end
        end
        schema.required = #new_req > 0 and new_req or nil
    end
    for _, kw in ipairs({"allOf", "anyOf", "oneOf"}) do
        if schema[kw] then
            for _, sub in ipairs(schema[kw]) do
                strip_required(sub, removed)
            end
        end
    end
    -- Handle if/then/else conditional schemas
    for _, kw in ipairs({"then", "else"}) do
        if schema[kw] then
            strip_required(schema[kw], removed)
        end
    end
    -- Handle dependencies (e.g., jwt-auth: dependencies.algorithm.oneOf[].required)
    if schema.dependencies then
        for _, dep in pairs(schema.dependencies) do
            if type(dep) == "table" then
                strip_required(dep, removed)
            end
        end
    end
end


-- Check if a schema (possibly using anyOf/oneOf/allOf composition)
-- accepts string values.
local function schema_accepts_string(sub_schema)
    if sub_schema.type == "string" then
        return true
    end
    for _, kw in ipairs({"anyOf", "oneOf", "allOf"}) do
        if sub_schema[kw] then
            for _, branch in ipairs(sub_schema[kw]) do
                if schema_accepts_string(branch) then
                    return true
                end
            end
        end
    end
    return false
end


-- Find an object-typed branch in anyOf/oneOf/allOf that has properties.
local function find_object_branch(sub_schema)
    for _, kw in ipairs({"anyOf", "oneOf", "allOf"}) do
        if sub_schema[kw] then
            for _, branch in ipairs(sub_schema[kw]) do
                if branch.type == "object" or branch.properties then
                    return branch
                end
            end
        end
    end
    return nil
end


local function strip_secret_refs(conf, schema)
    if type(conf) ~= "table" or type(schema) ~= "table" then
        return
    end

    -- lazy require to avoid circular dependency (secret -> core -> schema)
    local secret = require("apisix.secret")

    local props = schema.properties
    local removed = {}

    for k, v in pairs(conf) do
        if type(v) == "string" and secret.is_secret_ref(v) then
            conf[k] = nil
            tab_insert(removed, k)
            if props then
                props[k] = nil
            end
        elseif type(v) == "table" then
            local sub_schema = props and props[k]
            if sub_schema then
                if sub_schema.type == "object" or sub_schema.properties then
                    strip_secret_refs(v, sub_schema)
                elseif sub_schema.type == "array" and sub_schema.items then
                    if sub_schema.items.type == "string"
                       or schema_accepts_string(sub_schema.items)
                    then
                        local count = 0
                        for i = #v, 1, -1 do
                            if type(v[i]) == "string"
                               and secret.is_secret_ref(v[i])
                            then
                                tab_remove(v, i)
                                count = count + 1
                            end
                        end
                        if count > 0 and sub_schema.minItems then
                            sub_schema.minItems = math_max(
                                0, sub_schema.minItems - count
                            )
                        end
                    else
                        for _, item in ipairs(v) do
                            if type(item) == "table" then
                                strip_secret_refs(item, sub_schema.items)
                            end
                        end
                    end
                else
                    -- Handle anyOf/oneOf/allOf at property level that
                    -- resolve to object types with properties.
                    local obj_branch = find_object_branch(sub_schema)
                    if obj_branch then
                        strip_secret_refs(v, obj_branch)
                    end
                end
            end
        end
    end

    if #removed > 0 then
        strip_required(schema, removed)
        if schema.minProperties then
            schema.minProperties = math_max(
                0, schema.minProperties - #removed
            )
        end
    end
end


local function merge_defaults(orig, validated)
    for k, v in pairs(validated) do
        if orig[k] == nil then
            orig[k] = v
        elseif type(v) == "table" and type(orig[k]) == "table" then
            merge_defaults(orig[k], v)
        end
    end
end


function _M.check(schema, json)
    if type(json) == "table" then
        local secret = require("apisix.secret")
        if secret.has_secret_ref(json) then
            local deepcopy = require("apisix.core.table").deepcopy
            local schema_copy = deepcopy(schema)
            local json_copy = deepcopy(json)
            strip_secret_refs(json_copy, schema_copy)
            local validator, err = get_validator(schema_copy)
            if not validator then
                return false, err
            end
            local ok, err2 = validator(json_copy)
            if not ok then
                return false, err2
            end
            -- Validator sets default values on json_copy; merge them back
            -- into the original so defaults like upstream.scheme are preserved.
            merge_defaults(json, json_copy)
            return true
        end
    end

    local validator, err = get_validator(schema)

    if not validator then
        return false, err
    end

    return validator(json)
end

_M.valid = get_validator

setmetatable(_M, {
    __index = schema_def,
    __newindex = function() error("no modification allowed") end,
})

return _M
