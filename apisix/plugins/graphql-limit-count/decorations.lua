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
--
-- Runtime view of the GraphQL cost decorations.
--
-- Decorations are a sub resource of the service, so they arrive through the
-- services config watcher (`apisix/http/service.lua`) together with the services
-- themselves -- the same way consumer credentials arrive through the consumers
-- watcher. This module only has to pick them out and group them by service.
--
local core    = require("apisix.core")
local service = require("apisix.http.service")
local cost    = require("apisix.plugins.graphql-limit-count.cost")

local ipairs   = ipairs
local pairs    = pairs
local type     = type
local tostring = tostring

local _M = {}


local function build_index(values)
    local index = {}
    if not values then
        return index
    end

    local by_service = {}
    for _, item in ipairs(values) do
        if type(item) == "table" and service.is_graphql_cost_decoration_key(item.key) then
            local value = item.value
            if type(value) == "table" and value.service_id and value.field_path then
                local service_id = tostring(value.service_id)
                local per_service = by_service[service_id]
                if not per_service then
                    per_service = {}
                    by_service[service_id] = per_service
                end
                -- The Admin API rejects a duplicate field_path on the same service;
                -- should one appear anyway (a direct etcd write), the last one in
                -- etcd key order wins, which at least keeps the result deterministic.
                per_service[value.field_path] = value
            end
        end
    end

    -- Compile once per configuration version rather than per request; matching a
    -- field_path is a trie walk, not a string compare.
    for service_id, per_service in pairs(by_service) do
        local list = {}
        for _, value in pairs(per_service) do
            list[#list + 1] = value
        end
        index[service_id] = cost.build_index(list)
    end

    return index
end


---
-- Returns the compiled decoration index of a service, ready for
-- `cost.query_cost`, or nil when the service has none.
function _M.get(service_id)
    if not service_id then
        return nil
    end

    local values, conf_version = service.services()
    if not values then
        return nil
    end

    -- Rebuilt whenever anything under /services changes, which is coarser than
    -- necessary but is what apisix.consumer does for credentials too.
    local index = core.lrucache.global("/graphql_cost_decorations", conf_version,
                                       build_index, values)
    return index[tostring(service_id)]
end


return _M
