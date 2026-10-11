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
local core     = require("apisix.core")
local pairs    = pairs
local ipairs   = ipairs
local type     = type
local tostring = tostring

local _M = {}

-- OpenAPI-only keywords that are not valid JSON Schema.
local STRIP_KEYS = {
    "nullable", "xml", "externalDocs", "deprecated", "readOnly", "writeOnly",
}

local COMPOSITION_KEYS = { "allOf", "oneOf", "anyOf" }


local function convert(node, seen)
    if type(node) ~= "table" then
        return node
    end

    if node["$ref"] ~= nil then
        core.log.warn("unresolved $ref '", tostring(node["$ref"]), "', using generic object")
        return { type = "object" }
    end

    if seen[node] then
        core.log.warn("cycle detected in schema, using generic object to break recursion")
        return { type = "object" }
    end
    seen[node] = true

    local out = core.table.clone(node)

    -- "integer" is deliberately left alone rather than widened to "number":
    -- JSON Schema has an integer type of its own.

    -- read nullable before stripping it
    local nullable = out.nullable == true
    for _, key in ipairs(STRIP_KEYS) do
        out[key] = nil
    end

    if nullable then
        if type(out.type) == "table" then
            local has_null = false
            for _, t in ipairs(out.type) do
                if t == "null" then
                    has_null = true
                    break
                end
            end
            if not has_null then
                out.type[#out.type + 1] = "null"
            end
        elseif type(out.type) == "string" then
            out.type = { out.type, "null" }
        else
            out.type = "null"
        end
    end

    -- Deliberately checked *after* the nullable rewrite, which turns out.type
    -- into an array. A nullable object therefore stops recursing here, leaving
    -- OpenAPI-only keywords in its children. This is kept on purpose so the
    -- generated tool list stays stable for existing clients; the edge-case
    -- document in t/lib/mcp_edge_spec.lua pins it.
    if out.type == "object" and type(out.properties) == "table" then
        local props = {}
        for key, prop in pairs(out.properties) do
            props[key] = convert(prop, seen)
        end
        out.properties = props
    end

    if out.type == "array" and type(out.items) == "table" then
        out.items = convert(out.items, seen)
    end

    -- Composition keywords hold complete sub-schemas and are converted whether
    -- or not the parent carries a type.
    for _, keyword in ipairs(COMPOSITION_KEYS) do
        local branches = out[keyword]
        if type(branches) == "table" then
            local converted = {}
            for index, branch in ipairs(branches) do
                converted[index] = convert(branch, seen)
            end
            out[keyword] = converted
        end
    end

    seen[node] = nil
    return out
end


function _M.to_json_schema(oas_schema)
    return convert(oas_schema, {})
end


return _M
