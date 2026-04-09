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

--- Protocol detection and routing.
-- Detects the client protocol from the request body/URI by delegating
-- to each protocol's matches() method. Converter lookup is handled by
-- the converters/ registry.

local converters = require("apisix.plugins.ai-protocols.converters")
local ipairs = ipairs

local _M = {}


local registered = {
    ["openai-chat"] = require("apisix.plugins.ai-protocols.openai-chat"),
    ["openai-embeddings"] = require("apisix.plugins.ai-protocols.openai-embeddings"),
    ["anthropic-messages"] = require("apisix.plugins.ai-protocols.anthropic-messages"),
}

-- Detection order: URL+body first (anthropic), then body-only (chat, embeddings).
local detection_order = {
    { name = "anthropic-messages", protocol = registered["anthropic-messages"] },
    { name = "openai-chat",       protocol = registered["openai-chat"] },
    { name = "openai-embeddings", protocol = registered["openai-embeddings"] },
}


--- Detect the client protocol by asking each protocol if it matches.
-- @param body table The parsed request body
-- @param ctx table The request context
-- @return string Protocol name: "openai-chat" | "openai-embeddings" | "anthropic-messages"
function _M.detect(body, ctx)
    for _, entry in ipairs(detection_order) do
        if entry.protocol.matches(body, ctx) then
            return entry.name
        end
    end
    return nil, "unsupported request format: no protocol matched"
end


--- Get the protocol module for a given protocol name.
-- @param name string The protocol name
-- @return table|nil The protocol module
function _M.get(name)
    return registered[name]
end


--- Find a converter that can bridge from client_protocol to a protocol
-- supported by the driver. Delegates to the converters registry.
-- @param client_protocol string The detected client protocol
-- @param capabilities table The driver's capabilities table
-- @return table|nil converter module, string|nil target protocol name
function _M.find_converter(client_protocol, capabilities)
    return converters.find(client_protocol, capabilities)
end


-- Convenience wrappers: auto-detect protocol, dispatch to module.
-- Used by plugins that run before ai-proxy (prompt-guard, prompt-decorator, etc.)

local function get_proto(body, ctx)
    local name = _M.detect(body, ctx)
    return name and registered[name]
end


--- Get messages in canonical {role, content} format from any protocol.
function _M.get_messages(body, ctx)
    local proto = get_proto(body, ctx)
    return proto and proto.get_messages(body) or {}
end


--- Prepend messages to the request body (protocol-aware).
-- Falls back to openai-chat when no protocol is detected (e.g. body built from scratch by ai-rag).
function _M.prepend_messages(body, ctx, msgs)
    local proto = get_proto(body, ctx) or registered["openai-chat"]
    if proto then
        proto.prepend_messages(body, msgs)
    end
end


--- Append messages to the request body (protocol-aware).
-- Falls back to openai-chat when no protocol is detected (e.g. body built from scratch by ai-rag).
function _M.append_messages(body, ctx, msgs)
    local proto = get_proto(body, ctx) or registered["openai-chat"]
    if proto then
        proto.append_messages(body, msgs)
    end
end


--- Get raw request content for logging (protocol-aware).
function _M.get_request_content(body, ctx)
    local proto = get_proto(body, ctx)
    return proto and proto.get_request_content(body)
end


return _M
