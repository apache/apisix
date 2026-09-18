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
local http       = require("resty.http")
local lyaml      = require("lyaml")
local pcall      = pcall
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local str_find   = string.find
local str_sub    = string.sub
local str_gsub   = string.gsub
local table_sort = table.sort
local re_gmatch  = ngx.re.gmatch
local re_find    = ngx.re.find

local _M = {}

local DEFAULT_TIMEOUT = 5000

-- A JSON key is quoted and may escape the solidus as "\/" -- cjson does this by
-- default, and several other encoders offer it -- so the key cannot be matched
-- by looking for a bare leading slash. Capture any quoted key and unescape it
-- instead. YAML keys are bare and need their own pattern.
local JSON_KEY_RE = [=["((?:[^"\\]|\\.)*)"\s*:]=]
local YAML_KEY_RE = [=[^[ \t]*(/[^\s:]*)[ \t]*:]=]


local function unescape_json_key(key)
    if not str_find(key, "\\", 1, true) then
        return key
    end
    key = str_gsub(key, "\\/", "/")
    key = str_gsub(key, '\\"', '"')
    key = str_gsub(key, "\\\\", "\\")
    return key
end


-- Scanning the whole document would let a description such as
-- "see /apple : the fruit" register a path before the real `paths` section
-- does, flipping the tool order. Start the scan at the section itself.
local function find_paths_start(body)
    local from = str_find(body, '"paths"', 1, true)
    if from then
        return from
    end
    return re_find(body, [[^[ \t]*paths[ \t]*:]], "jom") or 1
end


-- Record the order in which paths appear in the raw document. Lua tables are
-- unordered, but the tool list must follow document order, the order a
-- JavaScript implementation walking Object.entries() would produce.
local function extract_path_order(body, spec)
    local order = {}
    local seen = 0

    if type(spec.paths) ~= "table" then
        return order
    end

    local section = str_sub(body, find_paths_start(body))

    local function scan(pattern, flags, unescape)
        local iter, err = re_gmatch(section, pattern, flags)
        if not iter then
            core.log.warn("failed to scan path order: ", err)
            return 0
        end
        local matched = 0
        while true do
            local m, merr = iter()
            if merr then
                core.log.warn("failed to scan path order: ", merr)
                break
            end
            if not m then
                break
            end
            local path = unescape and unescape_json_key(m[1]) or m[1]
            if spec.paths[path] and not order[path] then
                seen = seen + 1
                order[path] = seen
                matched = matched + 1
            end
        end
        return matched
    end

    if scan(JSON_KEY_RE, "jo", true) == 0 then
        scan(YAML_KEY_RE, "jom", false)
    end

    -- Any path the scan missed goes after the known ones, sorted so the result
    -- stays deterministic across workers.
    local missing = {}
    for path in pairs(spec.paths) do
        if not order[path] then
            missing[#missing + 1] = path
        end
    end
    table_sort(missing)
    for _, path in ipairs(missing) do
        seen = seen + 1
        order[path] = seen
    end

    return order
end


function _M.parse(body)
    if type(body) ~= "string" or body == "" then
        return nil, nil, "empty openapi spec"
    end

    local spec = core.json.decode(body)
    if type(spec) ~= "table" then
        local ok, decoded = pcall(lyaml.load, body)
        if not ok or type(decoded) ~= "table" then
            return nil, nil, "failed to parse openapi spec as JSON or YAML"
        end
        spec = decoded
    end

    return spec, extract_path_order(body, spec), nil
end


-- Whether a parsed document is an OpenAPI document at all. Any JSON or YAML
-- parses, so without this a route pointed at the wrong URL -- an error page, an
-- index document, a spec that failed to render -- comes up as a healthy MCP
-- server with an empty tool list, and nothing anywhere says why. A document
-- with no `paths` is rejected for the same reason: there is nothing to serve
-- from it.
--
-- Only the route's own document is held to this. A document pulled in by an
-- external `$ref` is usually a fragment -- components, a single schema -- and
-- has neither key.
function _M.validate(spec)
    if type(spec) ~= "table" then
        return nil, "openapi spec is not an object"
    end
    -- YAML leaves an unquoted version as a number: "swagger: 2.0" and
    -- "openapi: 3.1" both parse that way, and only a two-dot version such as
    -- "3.0.0" comes back as a string. JSON documents always quote it.
    local version = spec.openapi or spec.swagger
    if type(version) ~= "string" and type(version) ~= "number" then
        return nil, "not an openapi document: no openapi or swagger version"
    end
    -- OpenAPI 3.1 lets a document carry webhooks or components alone, so the
    -- absence of paths is not proof that this is not an OpenAPI document. It
    -- does mean there is nothing to turn into tools, which the caller reports
    -- as its own error rather than as "this is not an OpenAPI document".
    if type(spec.paths) ~= "table" then
        if type(spec.webhooks) == "table" or type(spec.components) == "table" then
            return nil, "openapi document declares no paths"
        end
        return nil, "not an openapi document: no paths object"
    end
    return true
end


function _M.fetch(url, timeout)
    local httpc, err = http.new()
    if not httpc then
        return nil, nil, "failed to create http client: " .. tostring(err)
    end
    httpc:set_timeout(timeout or DEFAULT_TIMEOUT)

    local res, req_err = httpc:request_uri(url, { method = "GET" })
    if not res then
        return nil, nil, "failed to fetch openapi spec: " .. tostring(req_err)
    end
    if res.status ~= 200 then
        return nil, nil, "unexpected status " .. res.status .. " while fetching openapi spec"
    end

    return _M.parse(res.body)
end


return _M
