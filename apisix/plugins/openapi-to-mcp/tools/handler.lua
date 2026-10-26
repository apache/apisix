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
local fetch        = require("apisix.plugins.openapi-to-mcp.fetch")
local json_pretty  = require("apisix.plugins.openapi-to-mcp.json_pretty")
local pairs        = pairs
local ipairs       = ipairs
local type         = type
local getmetatable = getmetatable
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

-- How much of an upstream response is read before the call is failed.
local DEFAULT_MAX_BODY = 1024 * 1024
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
local function container(arguments, key)
    local value = arguments[key]
    return type(value) == "table" and value or {}
end


-- Both shapes are filtered against what the operation declares. The generated
-- input schema does not forbid extra properties, and an operation that declares
-- no header parameter gets no headerParameters container to constrain either,
-- so an argument the document never mentioned would otherwise reach the API --
-- letting a caller add or replace request headers, the route's credentials
-- among them.
local function split_arguments(tool, arguments)
    local path_names = path_param_names(tool.path_template)
    local query_names = names_by_location(tool, "query")
    local header_names = names_by_location(tool, "header")

    local nested = false
    for _, key in ipairs(NESTED_KEYS) do
        if arguments[key] ~= nil then
            nested = true
            break
        end
    end

    if nested then
        return pick(container(arguments, "pathParameters"), path_names),
               pick(container(arguments, "queryParameters"), query_names),
               pick(container(arguments, "headerParameters"), header_names)
    end

    return pick(arguments, path_names),
           pick(arguments, query_names),
           pick(arguments, header_names)
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


local function sorted_keys(tab)
    -- Lua tables are unordered; sort so the query string is the same on every
    -- worker
    local keys = {}
    for key in pairs(tab) do
        keys[#keys + 1] = key
    end
    table_sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end


local function scalar(value)
    if type(value) == "table" then
        return core.json.encode(value) or ""
    end
    return tostring(value)
end


local function is_array(value)
    return #value > 0 or getmetatable(value) == core.json.array_mt
end


local DELIMITERS = {
    form = ",",
    spaceDelimited = "%20",
    pipeDelimited = "|",
}


-- Serialize one query parameter the way its Parameter Object says:
-- https://spec.openapis.org/oas/v3.0.3#style-values
-- `style` defaults to form, and `explode` defaults to true for form and false
-- otherwise.
--
--   value              form, explode      form, no explode   space/pipeDelimited   deepObject
--   tags = {a, b}      tags=a&tags=b      tags=a,b           tags=a%20b / a|b      -
--   f = {x = 1}        x=1                f=x,1              -                     f[x]=1
local function encode_query_param(name, value, param, parts)
    local style = type(param) == "table" and param.style or "form"
    local explode = type(param) == "table" and param.explode
    if explode == nil then
        explode = style == "form"
    end

    local ename = escape_uri(name)
    if type(value) ~= "table" then
        parts[#parts + 1] = ename .. "=" .. escape_uri(tostring(value))
        return
    end

    if is_array(value) then
        if #value == 0 then
            return
        end
        if explode then
            for _, item in ipairs(value) do
                parts[#parts + 1] = ename .. "=" .. escape_uri(scalar(item))
            end
            return
        end
        local items = {}
        for i, item in ipairs(value) do
            items[i] = escape_uri(scalar(item))
        end
        parts[#parts + 1] = ename .. "=" .. table_concat(items, DELIMITERS[style] or ",")
        return
    end

    local keys = sorted_keys(value)
    if #keys == 0 then
        return
    end

    if style == "deepObject" then
        for _, key in ipairs(keys) do
            parts[#parts + 1] = ename .. "%5B" .. escape_uri(tostring(key)) .. "%5D="
                                .. escape_uri(scalar(value[key]))
        end
        return
    end

    if explode then
        for _, key in ipairs(keys) do
            parts[#parts + 1] = escape_uri(tostring(key)) .. "=" .. escape_uri(scalar(value[key]))
        end
        return
    end

    local items = {}
    for _, key in ipairs(keys) do
        items[#items + 1] = escape_uri(tostring(key))
        items[#items + 1] = escape_uri(scalar(value[key]))
    end
    parts[#parts + 1] = ename .. "=" .. table_concat(items, ",")
end


local function build_query(tool, query)
    local keys = sorted_keys(query)
    if #keys == 0 then
        return nil
    end

    local params = {}
    for _, param in ipairs(tool.parameters or {}) do
        if type(param) == "table" and param["in"] == "query" then
            params[param.name] = param
        end
    end

    local parts = {}
    for _, key in ipairs(keys) do
        encode_query_param(tostring(key), query[key], params[key], parts)
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


-- Headers a tool call may not contribute, whatever the document declares.
--
-- The framing ones decide where this request ends and the next one begins.
-- resty.http drops Content-Length as soon as a Transfer-Encoding says chunked
-- and then writes the body exactly as given, unchunked: the caller would be
-- writing the frame boundaries of a request the gateway is sending, and the
-- connection goes back to the pool afterwards for the next tool call to reuse.
-- A short Content-Length does the same thing by leaving the rest of the body
-- to be read as another request.
--
-- The rest are hop-by-hop, or belong to the connection the gateway opened
-- rather than to the call: Host picks the virtual host, Connection and Upgrade
-- decide what happens to the connection itself.
--
-- This applies to the arguments of a call, not to the Route's own headers: an
-- operator naming one of these means it.
local FORBIDDEN_PARAM_HEADERS = {
    ["transfer-encoding"] = true,
    ["content-length"] = true,
    ["connection"] = true,
    ["keep-alive"] = true,
    ["host"] = true,
    ["upgrade"] = true,
    ["expect"] = true,
    ["te"] = true,
    ["trailer"] = true,
    ["proxy-authenticate"] = true,
    ["proxy-authorization"] = true,
}


-- Writes a header under one spelling per name.
--
-- Header names are case-insensitive, and the client normalises them at the
-- end, so "Authorization" and "authorization" are the same header there but
-- two keys in a plain Lua table. Both would survive to the client, which
-- resolves the collision in pairs() order -- the caller's copy would win
-- whenever the hash order put it last, and the Route's credential would be the
-- one replaced. Keeping one entry per lowercased name makes the later write
-- the one that counts, which is what "the Route's headers win" requires.
local function put_header(headers, seen, name, value)
    local lower = str_lower(name)
    local spelling = seen[lower]
    if spelling then
        headers[spelling] = value
        return
    end
    seen[lower] = name
    headers[name] = value
end


function _M.call(tool, arguments, opts)
    arguments = type(arguments) == "table" and arguments or {}

    local path_params, query_params, header_params = split_arguments(tool, arguments)
    apply_query_defaults(tool, query_params)

    local path = build_path(tool.path_template, path_params)
    local query = build_query(tool, query_params)

    -- Header parameters are written first so that the route's own headers win:
    -- they carry the credentials the gateway adds, and a tool call must not be
    -- able to replace them. Both sources are checked: a route header is a
    -- template resolved against the request, so its value is not fixed either.
    local headers, seen = {}, {}
    for key, value in pairs(header_params) do
        if FORBIDDEN_PARAM_HEADERS[str_lower(key)] then
            core.log.warn("dropped the header parameter ", key,
                          ": a tool call cannot set this header")
        elseif fetch.header_is_sane(key, value) then
            put_header(headers, seen, key, tostring(value))
        else
            core.log.warn("dropped a header parameter whose name or value ",
                          "cannot appear in a request header")
        end
    end
    for key, value in pairs(opts.headers or {}) do
        if fetch.header_is_sane(key, value) then
            put_header(headers, seen, key, value)
        else
            core.log.warn("dropped a configured header whose resolved name or ",
                          "value cannot appear in a request header")
        end
    end

    local body = arguments.requestBody
    if body ~= nil then
        if type(body) ~= "string" then
            body = core.json.encode(body)
        end
        -- Label the body with the media type the operation declares, unless the
        -- route's headers or a header parameter already set one.
        if not seen["content-type"] then
            put_header(headers, seen, "Content-Type",
                       tool.request_body_content_type or "application/json")
        end
    end

    local base_url = opts.base_url or ""
    if str_find(base_url, "/$") then
        base_url = str_gsub(base_url, "/$", "")
    end
    local url = base_url .. path
    if query then
        url = url .. "?" .. query
    end

    local res, req_err = fetch.request(url, {
        method = str_gsub(str_lower(tool.method), "^%l", str_upper),
        headers = headers,
        body = body,
        timeout = opts.timeout or DEFAULT_TIMEOUT,
        max_body_size = (opts.conf and opts.conf.max_response_body_size) or DEFAULT_MAX_BODY,
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

    if res.truncated then
        local limit = (opts.conf and opts.conf.max_response_body_size) or DEFAULT_MAX_BODY
        core.log.warn("upstream response exceeded max_response_body_size (", limit, " bytes)")
        return text_result({
            status = res.status,
            statusText = res.reason or "",
            headers = lower_headers(res.headers),
            data = core.json.null,
            error = {
                message = "response body exceeds max_response_body_size (" .. limit .. " bytes)",
                code = "RESPONSE_TOO_LARGE",
            },
        }, true)
    end

    return text_result({
        status = res.status,
        statusText = res.reason or "",
        headers = lower_headers(res.headers),
        data = decode_body(res.body),
    })
end


return _M
