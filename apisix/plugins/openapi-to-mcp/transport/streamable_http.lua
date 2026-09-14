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
local cache    = require("apisix.plugins.openapi-to-mcp.cache")
local server   = require("apisix.plugins.openapi-to-mcp.server")
local protocol = require("apisix.plugins.openapi-to-mcp.protocol")
local jsonrpc  = require("apisix.plugins.openapi-to-mcp.jsonrpc")
local table_concat = table.concat
local ngx      = ngx
local ngx_print = ngx.print
local ngx_flush = ngx.flush
local ngx_exit  = ngx.exit
local str_find  = string.find
local type      = type
local setmetatable = setmetatable
local tostring  = tostring

local _M = {}

local SERVER_ERROR_CODE = -32000

-- Transport-level rejections are answered with a JSON-RPC envelope and the HTTP
-- status the MCP spec calls for.
local function transport_error(status, message, data)
    return core.response.exit(status, {
        jsonrpc = "2.0",
        error = { code = SERVER_ERROR_CODE, message = message, data = data },
        id = core.json.null,
    })
end


-- The stateless handler builds its server -- which means fetching and parsing
-- the document -- before it looks at the message, so a document that cannot be
-- built fails every request that gets that far, ping and initialize included,
-- with this exact envelope.
local function stateless_internal_error(err)
    return core.response.exit(500, {
        jsonrpc = "2.0",
        error = {
            code = jsonrpc.ERR_INTERNAL,
            message = "Internal error: Failed to process stateless request",
            data = { mode = "stateless", error = tostring(err) },
        },
        id = core.json.null,
    })
end


local function is_json_content_type(content_type)
    if type(content_type) ~= "string" then
        return false
    end
    return str_find(content_type, "application/json", 1, true) ~= nil
end


-- MCP 2025-06-18 has the client repeat the negotiated version in a header on
-- every request after initialize. The SDK rejects a value it does not know;
-- absent is fine (a 2025-03-26 client never sends one), and initialize itself is
-- exempt, since that is the request doing the negotiating.
local SUPPORTED_LIST = table_concat(protocol.SUPPORTED_VERSIONS, ", ")


local function unsupported_protocol_version(request, ctx)
    if request.method == "initialize" then
        return nil
    end
    local header = core.request.header(ctx, "mcp-protocol-version")
    if header == nil or protocol.is_supported(header) then
        return nil
    end
    return header
end


-- MCP's Streamable HTTP binding requires the client to accept both media types;
-- the SDK rejects anything else before the message is even parsed.
local function accepts_both(accept)
    if type(accept) ~= "string" then
        return false
    end
    return str_find(accept, "application/json", 1, true) ~= nil
       and str_find(accept, "text/event-stream", 1, true) ~= nil
end


-- An empty or unparsable JSON body is answered ahead of every check below, a
-- bad Accept header included. A body that parses to a scalar is not this case: it gets as far as
-- JSON-RPC validation.
local function body_unparsable(ctx)
    if not is_json_content_type(core.request.header(ctx, "content-type")) then
        return false
    end
    if ctx._request_body_table ~= nil then
        return false
    end
    return core.request.get_json_request_body_table() == nil
end


local ALLOWED_METHODS = setmetatable({ "POST" }, core.json.array_mt)


function _M.handle(ctx, opts)
    local http_method = core.request.get_method()
    if http_method ~= "POST" then
        return transport_error(405, "Method Not Allowed: " .. http_method ..
                               " requests are not supported for stateless MCP endpoint",
                               { mode = "stateless", allowedMethods = ALLOWED_METHODS })
    end

    if body_unparsable(ctx) then
        return core.response.exit(400, jsonrpc.invalid_message())
    end

    -- The document is cached, so this is the fetch the first tools/list would
    -- have paid for anyway; it only costs anything when the build fails.
    local _, tools_err = cache.get_tools(opts.conf)
    if tools_err then
        core.log.error("failed to build the MCP tool list: ", tools_err)
        return stateless_internal_error(tools_err)
    end

    if not accepts_both(core.request.header(ctx, "accept")) then
        return transport_error(406, "Not Acceptable: Client must accept both " ..
                               "application/json and text/event-stream")
    end

    if not is_json_content_type(core.request.header(ctx, "content-type")) then
        return transport_error(415, "Unsupported Media Type: " ..
                               "Content-Type must be application/json")
    end

    -- body_unparsable() above already decoded and cached this body; do not
    -- decode a second time.
    local request = ctx._request_body_table
    if type(request) ~= "table" then
        local body, err = core.request.get_json_request_body_table()
        if type(body) ~= "table" then
            core.log.warn("failed to parse MCP request body: ",
                          type(err) == "table" and err.message or err)
            return core.response.exit(400, jsonrpc.invalid_message())
        end
        request = body
    end

    if not jsonrpc.validate(request) then
        return core.response.exit(400, jsonrpc.invalid_message())
    end

    -- after the message is validated and before it is dispatched, which is where
    -- the SDK checks it
    local bad_version = unsupported_protocol_version(request, ctx)
    if bad_version then
        return transport_error(400, "Bad Request: Unsupported protocol version: " ..
                               bad_version .. " (supported versions: " ..
                               SUPPORTED_LIST .. ")")
    end

    local response = server.handle(request, opts)
    if not response then
        -- notification: accepted, nothing to answer. No body means no content
        -- type; the plugin sets application/json for every reply that has one.
        core.response.set_header("Content-Type", nil)
        return core.response.exit(202)
    end

    local encoded, err = core.json.encode(response)
    if not encoded then
        core.log.error("failed to encode MCP response: ", err)
        return core.response.exit(500)
    end

    ngx.status = 200
    core.response.set_header("Content-Type", "text/event-stream")
    core.response.set_header("Cache-Control", "no-cache")
    ngx_print("event: message\ndata: ", encoded, "\n\n")

    local flushed, flush_err = ngx_flush(true)
    if not flushed then
        -- nothing to recover here; the client is already gone
        core.log.info("client left before the MCP response was flushed: ", flush_err)
    end

    return ngx_exit(200)
end


return _M
