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

--- Converter registry for protocol adapters.
-- Each converter module is a standalone file that declares its `from` and `to`
-- protocol names. To add a new converter, create a new module file in this
-- directory and add a require() line below — no other core code changes needed.

local pairs = pairs

local _M = {}

-- Registry: [from_protocol][to_protocol] = converter_module
local registry = {}


local function register(converter)
    local from = converter.from
    local to = converter.to
    if not registry[from] then
        registry[from] = {}
    end
    registry[from][to] = converter
end


--- Find a converter that can bridge from client_protocol to a protocol
-- supported by the driver's capabilities.
-- @param client_protocol string The detected client protocol
-- @param capabilities table The driver's capabilities table
-- @return table|nil converter module, string|nil target protocol name
function _M.find(client_protocol, capabilities)
    local from_map = registry[client_protocol]
    if not from_map then
        return nil, nil
    end
    for target_protocol, converter in pairs(from_map) do
        if capabilities[target_protocol] then
            return converter, target_protocol
        end
    end
    return nil, nil
end


---------------------------------------------------------------------
-- Register all converters below.
-- To add a new converter, create a module file and add one line here.
---------------------------------------------------------------------

register(require(
    "apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat"))

register(require(
    "apisix.plugins.ai-protocols.converters.openai-embeddings-to-vertex-predict"))


return _M
