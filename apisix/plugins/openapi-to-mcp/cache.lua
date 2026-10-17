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
local core      = require("apisix.core")
local loader    = require("apisix.plugins.openapi-to-mcp.openapi.loader")
local ref       = require("apisix.plugins.openapi-to-mcp.openapi.ref")
local generator = require("apisix.plugins.openapi-to-mcp.tools.generator")
local tostring  = tostring
local table_concat = table.concat
local table_sort   = table.sort

local _M = {}

-- A generated tool list is kept for an hour, for up to 100 documents.
local SPEC_TTL   = 3600
local SPEC_COUNT = 100

-- A failed fetch is cached only briefly. Without neg_ttl core.lrucache caches
-- nothing on failure, which would let an unreachable spec host be re-dialed on
-- every single request; a long negative TTL would instead keep the route broken
-- long after the host recovers.
local NEG_TTL   = 5
local NEG_COUNT = 32

local CACHE_VERSION = "1"

-- invalid_stale: without it core.lrucache hands an expired entry back and
-- re-arms its TTL whenever the version still matches, and the version here
-- never changes, so a document updated at the same URL would never be fetched
-- again.
local lru = core.lrucache.new({
    ttl = SPEC_TTL,
    count = SPEC_COUNT,
    invalid_stale = true,
    neg_ttl = NEG_TTL,
    neg_count = NEG_COUNT,
})


-- The scheme, host and port the document came from. An external $ref is
-- followed to that origin without asking, so the port is part of it.
local function document_origin(openapi_url)
    return (ref.origin_of(openapi_url))
end


local function build_tools(openapi_url, flatten_parameters, allowed_ref_hosts,
                           max_document_size, max_expanded_nodes)
    local spec, path_order, err = loader.fetch(openapi_url, nil, max_document_size)
    if not spec then
        return nil, err
    end

    local ok, invalid = loader.validate(spec)
    if not ok then
        return nil, invalid
    end

    local resolved = ref.resolve(spec, {
        base_origin = document_origin(openapi_url),
        allowed_hosts = allowed_ref_hosts,
        max_document_size = max_document_size,
        max_expanded_nodes = max_expanded_nodes,
    })
    return generator.generate(resolved, path_order, {
        flatten_parameters = flatten_parameters,
    })
end


-- Returns the tool list for a plugin conf, building it on first use.
-- base_url and headers do not take part in the key: they affect how a tool is
-- invoked, never how it is generated.
-- allowed_ref_hosts decides which documents may be pulled in, and
-- max_document_size how large any of them may be, so two routes that differ in
-- either must not share an entry. The list is sorted so that the same set in
-- another order is the same key, and joined with a NUL, which cannot occur in
-- a host name: joining with a comma would make { "a.com,b.com" } -- one entry,
-- matching nothing -- collide with { "a.com", "b.com" }.
local function hosts_key(allowed)
    if not allowed or #allowed == 0 then
        return ""
    end
    local sorted = core.table.new(#allowed, 0)
    for i = 1, #allowed do
        sorted[i] = allowed[i]
    end
    table_sort(sorted)
    return table_concat(sorted, "\0")
end


function _M.get_tools(conf)
    local flatten_parameters = conf.flatten_parameters == true
    local allowed = conf.allowed_ref_hosts
    local max_document_size = conf.max_document_size
    local max_expanded_nodes = conf.max_expanded_nodes
    local key = conf.openapi_url .. "#" .. tostring(flatten_parameters) ..
                "#" .. tostring(max_document_size) ..
                "#" .. tostring(max_expanded_nodes) ..
                "#" .. hosts_key(allowed)
    return lru(key, CACHE_VERSION, build_tools, conf.openapi_url, flatten_parameters,
               allowed, max_document_size, max_expanded_nodes)
end


return _M
