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
local ipairs = ipairs
local type   = type

local _M = {}

-- Snapshot of @modelcontextprotocol/sdk 1.26.0's version table. Pinning it
-- here keeps the gateway's answer stable as the SDK moves on.
_M.LATEST_VERSION = "2025-11-25"

_M.SUPPORTED_VERSIONS = {
    "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07",
}

local SUPPORTED = {}
for _, version in ipairs(_M.SUPPORTED_VERSIONS) do
    SUPPORTED[version] = true
end

_M.SERVER_NAME     = "openapi2mcp"
-- the SSE transport reports a name of its own
_M.SSE_SERVER_NAME = "openapi2mcp-sse"
_M.SERVER_VERSION  = "0.0.1"


function _M.is_supported(version)
    return type(version) == "string" and SUPPORTED[version] == true
end


-- A version the server knows is echoed back; anything else falls back to the
-- newest one, matching the SDK's Server.oninitialize.
function _M.negotiate(requested)
    if type(requested) == "string" and SUPPORTED[requested] then
        return requested
    end
    return _M.LATEST_VERSION
end


-- A bare tools capability: the tool list of a route only changes with its
-- configuration, so there is no listChanged notification to advertise.
function _M.capabilities()
    return { tools = {} }
end


function _M.server_info(transport)
    if transport == "sse" then
        return { name = _M.SSE_SERVER_NAME, version = _M.SERVER_VERSION }
    end
    return { name = _M.SERVER_NAME, version = _M.SERVER_VERSION }
end


return _M
