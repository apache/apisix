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
local core   = require("apisix.core")
local ipairs = ipairs
local pairs  = pairs

local _M = {}

local function do_metadata(node, metadata)
    local metadata = node.metadata
    -- because metadata has already been checked in nodes_metadata,
    -- there is at least one role, if there is no metadata in node, it's must not matched
    if not metadata then
        return false
    end
    for key, values in pairs(metadata) do
        local matched = false
        for _, value in ipairs(values) do
            if metadata[key] == value then
                matched = true
                break
            end
        end
        if not matched then
            return false
        end
    end
    return true
end

local function nodes_metadata(nodes, metadata)
    if not nodes then
        return nil
    end

    -- fast path: there is not metadata roles, all nodes are available,
    -- and make a guarantee for do_metadata: at least one role
    if not metadata then
        return nodes
    end

    local result = {}
    for _, node in ipairs(nodes) do
        if do_metadata(node, metadata) then
            core.table.insert(result, node)
        end
    end
    return result
end
_M.nodes_metadata = nodes_metadata

return _M
