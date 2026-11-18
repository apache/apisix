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

-- ref.resolve() expands the paths subtree of a document, because that is the
-- only part tools are generated from. The reference tests hand it a fragment
-- instead -- the shape under test, beside whatever its internal pointers
-- resolve against -- so this wraps the fragment in a document, keeping those
-- keys at the root where a "#/..." pointer looks for them, and hands back the
-- expansion of the fragment itself.
local ref   = require("apisix.plugins.openapi-to-mcp.openapi.ref")
local pairs = pairs
local setmetatable = setmetatable

local _M = setmetatable({}, { __index = ref })


function _M.resolve(fragment, opts)
    local spec = { paths = fragment }
    for key, value in pairs(fragment) do
        if key ~= "paths" then
            spec[key] = value
        end
    end
    return ref.resolve(spec, opts).paths
end


return _M
