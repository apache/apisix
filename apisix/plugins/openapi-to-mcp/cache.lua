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


local function build_tools(openapi_url, flatten_parameters)
    local spec, path_order, err = loader.fetch(openapi_url)
    if not spec then
        return nil, err
    end

    local ok, invalid = loader.validate(spec)
    if not ok then
        return nil, invalid
    end

    local resolved = ref.resolve(spec)
    return generator.generate(resolved, path_order, {
        flatten_parameters = flatten_parameters,
    })
end


-- Returns the tool list for a plugin conf, building it on first use.
-- base_url and headers do not take part in the key: they affect how a tool is
-- invoked, never how it is generated.
function _M.get_tools(conf)
    local flatten_parameters = conf.flatten_parameters == true
    local key = conf.openapi_url .. "#" .. tostring(flatten_parameters)
    return lru(key, CACHE_VERSION, build_tools, conf.openapi_url, flatten_parameters)
end


return _M
