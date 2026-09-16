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
local core       = require("apisix.core")
local endpoints  = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
local oas_schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
local pairs      = pairs
local ipairs     = ipairs
local next       = next
local type       = type
local tostring   = tostring
local str_sub    = string.sub
local str_gsub   = string.gsub
local str_upper  = string.upper
local str_lower  = string.lower
local str_gmatch = string.gmatch
local table_sort = table.sort

local _M = {}

local PARAM_LOCATIONS = { "path", "query", "header" }

local FLATTEN_DESC_PREFIX = {
    path   = "Path parameter: ",
    query  = "Query parameter: ",
    header = "Header parameter: ",
}

local NESTED_CONTAINER = {
    path   = "pathParameters",
    query  = "queryParameters",
    header = "headerParameters",
}

local ANNOTATION_EXTENSION = "x-mcp-annotations"

local BOOLEAN_ANNOTATION_KEYS = {
    "readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint",
}

local BOOLEAN_ANNOTATION_SET = {}
for _, key in ipairs(BOOLEAN_ANNOTATION_KEYS) do
    BOOLEAN_ANNOTATION_SET[key] = true
end


-- JavaScript treats "" as falsy, so `a || b || c` skips an empty description
-- and falls through to the next candidate. Lua's `or` does not, which would
-- leave `"description": ""` where there should be either nothing or the
-- generated default. petstore's deletePet carries exactly such a parameter.
local function present(str)
    if type(str) == "string" and str ~= "" then
        return str
    end
    return nil
end


local function trim(str)
    local out = str_gsub(str, "^%s*(.-)%s*$", "%1")
    return out
end


-- It lowercases the whole string first,
-- so "{userId}" becomes "Userid", not "UserId". Keep that.
function _M.title_case(str)
    local out = str_lower(str)
    out = str_gsub(out, "([-_/])(.)", function(_, char)
        return str_upper(char)
    end)
    out = str_gsub(out, "^{", "")
    out = str_gsub(out, "}$", "")
    out = str_gsub(out, "^.", str_upper)
    return out
end


-- "By" is only appended when the *last* segment is a path parameter, so
-- "get /users/{userId}/posts" yields "GetUsersPosts", not
-- "GetUsersPostsByUserId".
function _M.gen_operation_id(method, path)
    local parts = {}
    for part in str_gmatch(path, "[^/]+") do
        parts[#parts + 1] = part
    end

    local lower_method = str_lower(method)
    local name = lower_method

    for index, part in ipairs(parts) do
        if str_sub(part, 1, 1) == "{" and str_sub(part, -1) == "}" then
            if index == #parts then
                name = name .. "By" .. _M.title_case(part)
            end
        else
            name = name .. _M.title_case(part)
        end
    end

    if name == lower_method then
        name = name .. "Root"
    end

    return str_upper(str_sub(name, 1, 1)) .. str_sub(name, 2)
end


local function sanitize_name(name)
    local out = str_gsub(name, "%.", "_")
    out = str_gsub(out, "[^A-Za-z0-9_%-]", "_")
    return out
end


local function infer_annotations(method)
    local upper = str_upper(method)
    if upper == "GET" or upper == "HEAD" or upper == "OPTIONS" then
        return { readOnlyHint = true }
    elseif upper == "DELETE" then
        return { destructiveHint = true, idempotentHint = true }
    elseif upper == "PUT" then
        return { idempotentHint = true }
    end
    return {}
end


local function extract_custom_annotations(operation, op_id)
    local raw = operation[ANNOTATION_EXTENSION]
    -- an array is not a valid annotation object; in Lua an array has [1] set
    if type(raw) ~= "table" or raw[1] ~= nil then
        return {}
    end

    local out = {}

    if raw.title ~= nil then
        if type(raw.title) == "string" and trim(raw.title) ~= "" then
            out.title = trim(raw.title)
        else
            core.log.warn("ignoring invalid ", ANNOTATION_EXTENSION,
                          ".title for operation ", tostring(op_id))
        end
    end

    for _, key in ipairs(BOOLEAN_ANNOTATION_KEYS) do
        if raw[key] ~= nil then
            if type(raw[key]) == "boolean" then
                out[key] = raw[key]
            else
                core.log.warn("ignoring invalid ", ANNOTATION_EXTENSION, ".", key,
                              " for operation ", tostring(op_id))
            end
        end
    end

    for key in pairs(raw) do
        if key ~= "title" and not BOOLEAN_ANNOTATION_SET[key] then
            core.log.warn("ignoring unsupported ", ANNOTATION_EXTENSION, ".", tostring(key),
                          " for operation ", tostring(op_id))
        end
    end

    return out
end


-- A remote OpenAPI document controls param.name. Using a nil name as a table
-- key raises "table index is nil" and takes down generation for the whole spec,
-- so a nameless parameter is dropped instead.
local function named(param, location)
    if type(param.name) == "string" and param.name ~= "" then
        return true
    end
    core.log.warn("skipping parameter without a name, in: ", location)
    return false
end


-- Swagger 2.0 puts the schema keywords directly on a non-body parameter instead
-- of under `schema`; reading them from the parameter itself is enough. Keyed on
-- `type` being a string, which a 3.0 `content`-style parameter never has.
local SWAGGER2_SCHEMA_KEYS = {
    "type", "format", "items", "default", "enum", "multipleOf",
    "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum",
    "maxLength", "minLength", "pattern", "maxItems", "minItems", "uniqueItems",
}


local function param_schema_source(param)
    if param.schema ~= nil then
        return param.schema
    end
    if type(param.type) ~= "string" then
        return nil
    end

    local inline = {}
    for _, key in ipairs(SWAGGER2_SCHEMA_KEYS) do
        inline[key] = param[key]
    end
    return inline
end


local function build_flat_params(params, properties, required)
    for _, location in ipairs(PARAM_LOCATIONS) do
        local prefix = FLATTEN_DESC_PREFIX[location]
        for _, param in ipairs(params) do
            if type(param) == "table" and param["in"] == location
               and named(param, location)
            then
                local param_schema = oas_schema.to_json_schema(param_schema_source(param))
                if type(param_schema) == "table" then
                    param_schema.description = present(param.description)
                                               or present(param_schema.description)
                                               or (prefix .. param.name)
                end
                -- a parameter with neither `schema` nor a 2.0 `type` yields
                -- nil, and the property is dropped
                properties[param.name] = param_schema
                if param.required then
                    required[#required + 1] = param.name
                end
            end
        end
    end
end


local function build_nested_params(params, properties, required)
    for _, location in ipairs(PARAM_LOCATIONS) do
        local container = {}
        local container_required = {}
        local matched = false

        for _, param in ipairs(params) do
            if type(param) == "table" and param["in"] == location
               and named(param, location)
            then
                local param_schema = oas_schema.to_json_schema(param_schema_source(param))
                if type(param_schema) == "table" then
                    param_schema.description = present(param.description)
                                               or present(param_schema.description)
                else
                    -- an empty schema still keeps the key
                    param_schema = {}
                end
                matched = true
                container.type = "object"
                container.properties = container.properties or {}
                container.properties[param.name] = param_schema
                if param.required then
                    container_required[#container_required + 1] = param.name
                end
            end
        end

        if matched then
            if #container_required > 0 then
                container.required = container_required
                required[#required + 1] = NESTED_CONTAINER[location]
            end
            container.additionalProperties = false
            properties[NESTED_CONTAINER[location]] = container
        end
    end
end


local function build_request_body(operation, properties, required)
    local request_body = operation.requestBody
    if type(request_body) ~= "table" then
        return nil
    end

    local content = request_body.content
    if type(content) ~= "table" then
        return nil
    end

    local json_content = content["application/json"]
    if type(json_content) == "table" and json_content.schema ~= nil then
        local body_schema = oas_schema.to_json_schema(json_content.schema)
        if type(body_schema) == "table" then
            body_schema.description = present(request_body.description)
                                      or present(body_schema.description)
                                      or "The JSON request body."
        end
        properties.requestBody = body_schema
        if request_body.required then
            required[#required + 1] = "requestBody"
        end
        return "application/json"
    end

    -- Document order would be the natural choice, but Lua tables are
    -- unordered, so pick the lexicographically smallest key to stay
    -- deterministic. Only reachable when a body declares several non-JSON
    -- content types.
    local types = {}
    for content_type in pairs(content) do
        types[#types + 1] = content_type
    end
    if #types == 0 then
        return nil
    end
    table_sort(types)
    local content_type = types[1]

    properties.requestBody = {
        type = "string",
        description = present(request_body.description)
                      or ("Request body (content type: " .. content_type .. ")"),
    }
    if request_body.required then
        required[#required + 1] = "requestBody"
    end
    return content_type
end


function _M.build_input_schema(operation, flatten_parameters)
    local properties = {}
    local required = {}

    local params = operation.parameters
    if type(params) ~= "table" then
        params = {}
    end

    if flatten_parameters then
        build_flat_params(params, properties, required)
    else
        build_nested_params(params, properties, required)
    end

    local request_body_content_type = build_request_body(operation, properties, required)

    local input_schema = { type = "object", properties = properties }
    if #required > 0 then
        input_schema.required = required
    end

    return input_schema, params, request_body_content_type
end


function _M.generate(spec, path_order, opts)
    opts = opts or {}
    local flatten_parameters = opts.flatten_parameters == true

    local tools = {}
    local used_names = {}

    for _, endpoint in ipairs(endpoints.extract(spec, path_order)) do
        local operation = endpoint.operation

        local base_name = operation.operationId
        if type(base_name) ~= "string" or base_name == "" then
            base_name = _M.gen_operation_id(endpoint.method, endpoint.path)
        end
        base_name = sanitize_name(base_name)

        local name = base_name
        local counter = 1
        while used_names[name] do
            name = base_name .. "_" .. counter
            counter = counter + 1
        end
        used_names[name] = true

        local description = present(operation.description) or present(operation.summary)
        if not description then
            description = "Executes " .. str_upper(endpoint.method) .. " " .. endpoint.path
        end

        local input_schema, params, content_type =
            _M.build_input_schema(operation, flatten_parameters)

        local execution_parameters = {}
        for index, param in ipairs(params) do
            execution_parameters[index] = { name = param.name, ["in"] = param["in"] }
        end

        local annotations = infer_annotations(endpoint.method)
        for key, value in pairs(extract_custom_annotations(operation, name)) do
            annotations[key] = value
        end
        if next(annotations) == nil then
            annotations = nil
        end

        tools[#tools + 1] = {
            name = name,
            description = description,
            input_schema = input_schema,
            method = endpoint.method,
            path_template = endpoint.path,
            parameters = params,
            execution_parameters = execution_parameters,
            request_body_content_type = content_type,
            annotations = annotations,
        }
    end

    return tools
end


return _M
