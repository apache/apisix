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
local core     = require("apisix.core")
local jsonrpc  = require("apisix.plugins.openapi-to-mcp.jsonrpc")
local protocol = require("apisix.plugins.openapi-to-mcp.protocol")
local cache    = require("apisix.plugins.openapi-to-mcp.cache")
local handler  = require("apisix.plugins.openapi-to-mcp.tools.handler")
local ipairs   = ipairs
local type     = type
local tostring = tostring
local setmetatable = setmetatable

local _M = {}


-- Internal tool records use snake_case; the wire format does not. The SDK also
-- emits an `execution` field, which is a property of the SDK's own task support
-- rather than of openapi-to-mcp, so it is deliberately not reproduced.
local function to_wire_tools(tools)
    local out = setmetatable({}, core.json.array_mt)
    for index, tool in ipairs(tools) do
        out[index] = {
            name = tool.name,
            description = tool.description,
            inputSchema = tool.input_schema,
            annotations = tool.annotations,
        }
    end
    return out
end


local function find_tool(tools, name)
    for _, tool in ipairs(tools) do
        if tool.name == name then
            return tool
        end
    end
    return nil
end


local function tool_error(id, message)
    return jsonrpc.result(id, {
        content = { { type = "text", text = message } },
        isError = true,
    })
end


local function handle_tools_call(request, opts, tools)
    local params = request.params or {}
    local name = params.name

    if type(name) ~= "string" then
        return tool_error(request.id, "MCP error -32602: Tool name is required")
    end

    local tool = find_tool(tools, name)
    if not tool then
        return tool_error(request.id, "MCP error -32602: Tool " .. name .. " not found")
    end

    local arguments = type(params.arguments) == "table" and params.arguments or {}

    local ok, err = core.schema.check(tool.input_schema, arguments)
    if not ok then
        -- The MCP SDK embeds its validator's error array here. jsonschema words
        -- its failures differently, so only the prefix is reproduced; clients
        -- key off isError, not the wording.
        return tool_error(request.id, "MCP error -32602: Input validation error: " ..
                          "Invalid arguments for tool " .. name .. ": " .. tostring(err))
    end

    return jsonrpc.result(request.id, handler.call(tool, arguments, opts))
end


-- Returns the response table, or nil for a notification (the caller answers 202).
-- The request has already passed jsonrpc.validate() in the transport.
function _M.handle(request, opts)
    if jsonrpc.is_notification(request) then
        return nil
    end

    local method = request.method
    local params = request.params or {}

    if method == "initialize" then
        return jsonrpc.result(request.id, {
            protocolVersion = protocol.negotiate(params.protocolVersion),
            capabilities = protocol.capabilities(),
            serverInfo = protocol.server_info(opts.transport),
        })
    end

    if method == "ping" then
        return jsonrpc.result(request.id, {})
    end

    if method == "tools/list" or method == "tools/call" then
        local tools, err = cache.get_tools(opts.conf)
        if not tools then
            return jsonrpc.error(request.id, jsonrpc.ERR_INTERNAL,
                                 "failed to load openapi spec: " .. tostring(err))
        end

        if method == "tools/list" then
            return jsonrpc.result(request.id, { tools = to_wire_tools(tools) })
        end
        return handle_tools_call(request, opts, tools)
    end

    return jsonrpc.error(request.id, jsonrpc.ERR_METHOD_NOT_FOUND, "Method not found")
end


return _M
