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
local http         = require("resty.http")
local json_pretty  = require("apisix.plugins.openapi-to-mcp.json_pretty")
local pairs        = pairs
local ipairs       = ipairs
local type         = type
local tostring     = tostring
local str_lower    = string.lower
local str_upper    = string.upper
local str_gsub     = string.gsub
local str_gmatch   = string.gmatch
local str_find     = string.find
local table_concat = table.concat
local table_sort   = table.sort
local escape_uri   = ngx.escape_uri

local _M = {}

local DEFAULT_TIMEOUT = 30000
local NESTED_KEYS = { "pathParameters", "queryParameters", "headerParameters" }


local function path_param_names(template)
    local names = {}
    for name in str_gmatch(template, "{([^}]+)}") do
        names[#names + 1] = name
    end
    return names
end


local function names_by_location(tool, location)
    local names = {}
    for _, param in ipairs(tool.parameters or {}) do
        if type(param) == "table" and param["in"] == location then
            names[#names + 1] = param.name
        end
    end
    return names
end


local function pick(arguments, names)
    local out = {}
    for _, name in ipairs(names) do
        if arguments[name] ~= nil then
            out[name] = arguments[name]
        end
    end
    return out
end


-- Whether the caller used the flat or the nested argument shape is decided by
-- the arguments themselves, not by the plugin's flatten_parameters setting.
-- A client that sends flat arguments to a nested tool therefore still works.
local function split_arguments(tool, arguments)
    local nested = false
    for _, key in ipairs(NESTED_KEYS) do
        if arguments[key] ~= nil then
            nested = true
            break
        end
    end

    if nested then
        return type(arguments.pathParameters) == "table" and arguments.pathParameters or {},
               type(arguments.queryParameters) == "table" and arguments.queryParameters or {},
               type(arguments.headerParameters) == "table" and arguments.headerParameters or {}
    end

    return pick(arguments, path_param_names(tool.path_template)),
           pick(arguments, names_by_location(tool, "query")),
           pick(arguments, names_by_location(tool, "header"))
end


local function apply_query_defaults(tool, query)
    for _, param in ipairs(tool.parameters or {}) do
        if type(param) == "table" and param["in"] == "query"
           and type(param.schema) == "table"
           and param.schema.default ~= nil
           and query[param.name] == nil
        then
            query[param.name] = param.schema.default
        end
    end
end


local function build_path(template, path_params)
    local path = template
    for name, value in pairs(path_params) do
        -- the name is a literal, so escape any pattern magic in it
        local pattern = "{" .. str_gsub(name, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "}"
        local escaped = escape_uri(tostring(value))
        -- The replacement has to be a function: percent-encoding produces "%2F"
        -- and friends, and gsub would read those as capture references in a
        -- string replacement and raise "invalid capture index".
        path = str_gsub(path, pattern, function()
            return escaped
        end)
    end
    return path
end


-- Bracket notation, as the common JavaScript HTTP clients serialize it: an
-- array becomes "tags[]=a&tags[]=b" and an object "filter[a]=x", nested to any
-- depth. Dropping the brackets, or dropping objects entirely, would lose the
-- structure the schema advertised.
local function encode_param(name, value, parts)
    if type(value) ~= "table" then
        parts[#parts + 1] = escape_uri(name) .. "=" .. escape_uri(tostring(value))
        return
    end

    if #value > 0 then
        for _, item in ipairs(value) do
            encode_param(name .. "[]", item, parts)
        end
        return
    end

    -- Lua tables are unordered, so emit object members in sorted order to keep
    -- the query string deterministic across workers.
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table_sort(keys)
    for _, key in ipairs(keys) do
        encode_param(name .. "[" .. tostring(key) .. "]", value[key], parts)
    end
end


local function build_query(query)
    local keys = {}
    for key in pairs(query) do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        return nil
    end
    table_sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        encode_param(key, query[key], parts)
    end
    if #parts == 0 then
        return nil
    end
    return table_concat(parts, "&")
end


local function lower_headers(headers)
    local out = {}
    for key, value in pairs(headers or {}) do
        out[str_lower(key)] = value
    end
    return out
end


-- Every response body goes through a JSON decode and falls back to the raw
-- string, without looking at the content type.
local function decode_body(body)
    if body == nil or body == "" then
        return body
    end
    local decoded = core.json.decode(body)
    if decoded == nil then
        return body
    end
    return decoded
end


local function text_result(payload, is_error)
    local text, err = json_pretty.encode(payload)
    if not text then
        text = "failed to encode response: " .. tostring(err)
    end
    return {
        content = { { type = "text", text = text } },
        isError = is_error or nil,
    }
end


function _M.call(tool, arguments, opts)
    arguments = type(arguments) == "table" and arguments or {}

    local path_params, query_params, header_params = split_arguments(tool, arguments)
    apply_query_defaults(tool, query_params)

    local path = build_path(tool.path_template, path_params)
    local query = build_query(query_params)

    local headers = {}
    for key, value in pairs(opts.headers or {}) do
        headers[key] = value
    end
    for key, value in pairs(header_params) do
        headers[key] = tostring(value)
    end

    local body = arguments.requestBody
    if body ~= nil and type(body) ~= "string" then
        body = core.json.encode(body)
        headers["Content-Type"] = headers["Content-Type"] or "application/json"
    end

    local base_url = opts.base_url or ""
    if str_find(base_url, "/$") then
        base_url = str_gsub(base_url, "/$", "")
    end
    local url = base_url .. path
    if query then
        url = url .. "?" .. query
    end

    local httpc, client_err = http.new()
    if not httpc then
        return text_result({
            status = 0,
            statusText = "Network Error",
            headers = {},
            data = core.json.null,
            error = { message = tostring(client_err), code = "NETWORK_ERROR" },
        })
    end
    httpc:set_timeout(opts.timeout or DEFAULT_TIMEOUT)

    local res, req_err = httpc:request_uri(url, {
        method = str_gsub(str_lower(tool.method), "^%l", str_upper),
        headers = headers,
        body = body,
    })

    if not res then
        -- A transport failure is reported inside a normal text result, with
        -- isError unset: the call reached no API, so there is no API error.
        return text_result({
            status = 0,
            statusText = "Network Error",
            headers = {},
            data = core.json.null,
            error = { message = tostring(req_err), code = "NETWORK_ERROR" },
        })
    end

    return text_result({
        status = res.status,
        statusText = res.reason or "",
        headers = lower_headers(res.headers),
        data = decode_body(res.body),
    })
end


return _M
