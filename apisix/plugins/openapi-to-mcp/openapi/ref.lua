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
local http   = require("resty.http")
local loader       = require("apisix.plugins.openapi-to-mcp.openapi.loader")
local pairs        = pairs
local ipairs       = ipairs
local type         = type
local getmetatable = getmetatable
local setmetatable = setmetatable
local tostring     = tostring
local str_lower  = string.lower
local str_sub   = string.sub
local str_gsub  = string.gsub
local str_find  = string.find
local ngx_now   = ngx.now

local _M = {}

local MAX_DEPTH = 16
local GENERIC_OBJECT = "object"

-- An http(s) $ref is followed and the document it names is fetched, so a spec
-- that splits its schemas across files works. This runs in the request path
-- of the gateway itself, so a
-- document naming hundreds of hosts must not be able to turn one tools/list
-- into hundreds of outbound requests. The result is cached with the spec, so
-- these bounds apply once per hour per route, not once per request.
local EXTERNAL_TIMEOUT = 3000
local MAX_EXTERNAL_DOCS = 8
local EXTERNAL_BUDGET = 10

-- $ref expansion is inlining, so a document where every level fans out to
-- several refs grows as the product of those widths -- MAX_DEPTH alone leaves
-- room for billions of nodes. Expansion stops at this many nodes and degrades
-- what is left to a generic object.
local MAX_NODES = 50000


-- Split "#/a/b~1c" into { "a", "b/c" }. Returns nil for non-internal refs.
local function parse_pointer(ref)
    if type(ref) ~= "string" or str_sub(ref, 1, 2) ~= "#/" then
        return nil
    end

    local parts = {}
    local body = str_sub(ref, 3)
    local pos = 1
    while true do
        local sep = str_find(body, "/", pos, true)
        local seg = sep and str_sub(body, pos, sep - 1) or str_sub(body, pos)
        -- "~1" must be decoded before "~0", otherwise "~01" would become "/"
        seg = str_gsub(seg, "~1", "/")
        seg = str_gsub(seg, "~0", "~")
        parts[#parts + 1] = seg
        if not sep then
            break
        end
        pos = sep + 1
    end
    return parts
end


local function lookup(root, parts)
    local cur = root
    for _, seg in ipairs(parts) do
        if type(cur) ~= "table" then
            return nil
        end
        cur = cur[seg]
    end
    return cur
end


local function is_external(ref)
    return str_sub(ref, 1, 7) == "http://" or str_sub(ref, 1, 8) == "https://"
end


-- Fetches the document an external $ref names and returns the node it points
-- at, together with the document it came from: an internal $ref inside a
-- fetched document resolves against that document, not against the main spec.
-- An external $ref is a URL the document chooses, and the gateway is the one
-- dialling it. Only the host the document itself came from is followed by
-- default; anything else has to be named in allowed_ref_hosts, so a document
-- cannot point the gateway at a metadata service or an internal address.
local function host_allowed(url, ctx)
    local parsed = http:parse_uri(url, false)
    if not parsed then
        return false
    end
    local host = str_lower(parsed[2] or "")
    if host == "" then
        return false
    end
    if host == ctx.base_host then
        return true
    end
    for _, pattern in ipairs(ctx.allowed_hosts or {}) do
        local lower = str_lower(pattern)
        if lower == host then
            return true
        end
        if str_sub(lower, 1, 2) == "*." then
            local suffix = str_sub(lower, 2)
            if #host > #suffix and str_sub(host, -#suffix) == suffix then
                return true
            end
        end
    end
    return false
end


local function external_target(ref, ctx)
    local hash = str_find(ref, "#", 1, true)
    local url = hash and str_sub(ref, 1, hash - 1) or ref
    local fragment = hash and str_sub(ref, hash + 1) or ""

    if not host_allowed(url, ctx) then
        -- the URL is not logged: an external $ref can carry credentials in its
        -- userinfo or query string
        core.log.warn("an external $ref points at a host that is not allowed, ",
                      "using generic object")
        return nil
    end

    local doc = ctx.docs[url]
    if doc == nil then
        -- neither URL nor error is logged: an external $ref can carry
        -- credentials in its userinfo or query string
        if ctx.fetched >= MAX_EXTERNAL_DOCS then
            core.log.warn("too many external $ref documents, using generic object")
            return nil
        end
        if ctx.deadline and ngx_now() > ctx.deadline then
            core.log.warn("external $ref time budget exhausted, using generic object")
            return nil
        end
        ctx.deadline = ctx.deadline or (ngx_now() + EXTERNAL_BUDGET)
        ctx.fetched = ctx.fetched + 1

        doc = loader.fetch(url, EXTERNAL_TIMEOUT)
        if type(doc) ~= "table" then
            core.log.warn("failed to fetch an external $ref document, using generic object")
            doc = false
        end
        ctx.docs[url] = doc
    end

    if doc == false then
        return nil
    end
    if fragment == "" then
        return doc, doc
    end

    local parts = parse_pointer("#" .. fragment)
    if not parts then
        return nil
    end
    return lookup(doc, parts), doc
end


local function expand(node, root, depth, active, ctx)
    if type(node) ~= "table" then
        return node
    end

    ctx.nodes = ctx.nodes + 1
    if ctx.nodes > MAX_NODES then
        if not ctx.warned then
            core.log.warn("$ref expansion exceeded ", MAX_NODES,
                          " nodes, using generic object")
            ctx.warned = true
        end
        return { type = GENERIC_OBJECT }
    end

    if depth > MAX_DEPTH then
        core.log.warn("$ref expansion exceeded max depth ", MAX_DEPTH,
                      ", using generic object")
        return { type = GENERIC_OBJECT }
    end

    local ref = node["$ref"]
    if ref ~= nil then
        -- The same pointer means different things in different documents, so a
        -- cycle is a repeat of the pair, not of the pointer alone. A pointer
        -- already on the current expansion path degrades immediately rather
        -- than unrolling to MAX_DEPTH: cutting at the first repeat, as
        -- json-schema-ref-parser does with circular:"ignore", keeps the schema
        -- from growing many times the size of the reference.
        local key = tostring(root) .. "\0" .. tostring(ref)
        if active[key] then
            return { type = GENERIC_OBJECT }
        end

        local target, target_root
        local parts = parse_pointer(ref)
        if parts then
            target, target_root = lookup(root, parts), root
        elseif type(ref) == "string" and is_external(ref) then
            target, target_root = external_target(ref, ctx)
        else
            -- A relative or bare-file $ref would name a file on the gateway's
            -- own filesystem, which a route must not be able to read. The
            -- reference is not logged: it can carry credentials in its
            -- userinfo or query string.
            core.log.warn("only internal and http(s) $ref is supported, ",
                          "using generic object")
            return { type = GENERIC_OBJECT }
        end

        if type(target) ~= "table" then
            core.log.warn("failed to resolve $ref, using generic object")
            return { type = GENERIC_OBJECT }
        end

        active[key] = true
        -- $ref replaces the whole object; sibling keys are dropped per OpenAPI 3.0
        local expanded = expand(target, target_root, depth + 1, active, ctx)
        active[key] = nil
        return expanded
    end

    local out = {}
    -- an empty array must stay an array once re-encoded
    if getmetatable(node) == core.json.array_mt then
        setmetatable(out, core.json.array_mt)
    end
    for key, value in pairs(node) do
        out[key] = expand(value, root, depth, active, ctx)
    end
    return out
end


-- opts.base_host is the host openapi_url was fetched from, opts.allowed_hosts
-- the operator's extra allow-list for external $ref targets.
function _M.resolve(spec, opts)
    opts = opts or {}
    return expand(spec, spec, 0, {}, {
        docs = {},
        fetched = 0,
        nodes = 0,
        base_host = opts.base_host,
        allowed_hosts = opts.allowed_hosts,
    })
end


return _M
