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
local core           = require("apisix.core")
local cache          = require("apisix.plugins.openapi-to-mcp.cache")
local session        = require("apisix.plugins.openapi-to-mcp.session")
local server         = require("apisix.plugins.openapi-to-mcp.server")
local jsonrpc        = require("apisix.plugins.openapi-to-mcp.jsonrpc")
local ngx            = ngx
local str_find       = string.find
local ngx_print      = ngx.print
local ngx_flush      = ngx.flush
local ngx_exit       = ngx.exit
local ngx_sleep      = ngx.sleep
local ngx_now        = ngx.now
local worker_exiting = ngx.worker.exiting
local pairs          = pairs
local type           = type
local tostring       = tostring

local _M = {}

-- An idle session is dropped after 30 minutes.
local STREAM_MAX_LIFETIME = 1800

-- How often an idle stream emits an SSE comment. Comments start with ":" and
-- are ignored by every SSE client, so this does not alter the protocol; it
-- gives intermediaries something to see and refreshes the session marker.
--
-- It does not detect a client that went away. Writing to a dropped connection
-- reports no error here: that needs lua_check_client_abort, which is an
-- http-level directive and not one plugin's to turn on for the whole gateway.
-- A stream whose client is gone therefore runs until STREAM_MAX_LIFETIME; the
-- cost is one held connection and two shared
-- dict entries per abandoned stream, for at most half an hour. Measured, not
-- assumed: no write error appears after a FIN or an RST, past the keepalive.
local KEEPALIVE_INTERVAL = 30

local POLL_INTERVAL = 0.1


local function emit(chunk)
    local ok, err = ngx_print(chunk)
    if not ok then
        return nil, err
    end
    return ngx_flush(true)
end


-- The session id is what authorises a POST to this session's message endpoint,
-- so it is a bearer credential and stays out of the logs. Stream lifecycle
-- lines carry the reason, not the identifier.
-- "${...}" anywhere in base_url or a header value means the values depend on
-- the request they were resolved from.
local function uses_variables(conf)
    if type(conf.base_url) == "string" and str_find(conf.base_url, "${", 1, true) then
        return true
    end
    for _, value in pairs(conf.headers or {}) do
        if type(value) == "string" and str_find(value, "${", 1, true) then
            return true
        end
    end
    return false
end


local function handle_get(ctx, opts)
    -- Build the tool list -- which means fetching and parsing the document --
    -- before opening the stream, and answer 500 when that fails. Opening the
    -- stream first would let a route with an unreachable
    -- openapi_url look like a working connection to the client, and every
    -- request on it would fail instead. The result is cached, so this is the
    -- same fetch the first tools/list would have paid for.
    local _, tools_err = cache.get_tools(opts.conf)
    if tools_err then
        core.log.error("failed to build the MCP tool list: ", tools_err)
        return core.response.exit(500, {
            error = "Failed to create session",
            message = tools_err,
        })
    end

    -- Freeze what the stream resolved from this request, so every message POST
    -- on this session reaches the upstream with the same base_url and headers.
    -- Only when the configuration holds a variable: otherwise every POST
    -- resolves to the same values anyway, and the record would keep a copy of
    -- whatever those headers carry -- a caller's token among them -- in the
    -- shared dict for as long as the session lives.
    local context
    if uses_variables(opts.conf) then
        context = { base_url = opts.base_url, headers = opts.headers }
    end

    local session_id, err = session.create(context)
    if not session_id then
        core.log.error("failed to create MCP session: ", err)
        return core.response.exit(500)
    end

    ngx.status = 200
    core.response.set_header("Content-Type", "text/event-stream")
    -- no-transform keeps an intermediary
    -- from rewriting or compressing the event stream
    core.response.set_header("Cache-Control", "no-cache, no-transform")

    -- Tell the client where to POST its messages:
    -- "<message path>?sessionId=<uuid>".
    local endpoint = tostring(opts.message_path) .. "?sessionId=" .. session_id
    local ok, emit_err = emit("event: endpoint\ndata: " .. endpoint .. "\n\n")
    if not ok then
        core.log.info("MCP stream closed before start: ", emit_err)
        session.destroy(session_id)
        return ngx_exit(0)
    end

    local deadline = ngx_now() + STREAM_MAX_LIFETIME
    local last_keepalive = ngx_now()

    while not worker_exiting() do
        local message = session.pop(session_id)

        if message then
            local sent, send_err = emit("event: message\ndata: " .. message .. "\n\n")
            if not sent then
                core.log.info("MCP stream disconnected: ", send_err)
                break
            end
        else
            local now = ngx_now()
            if now > deadline then
                core.log.info("MCP stream reached its maximum lifetime")
                break
            end

            if now - last_keepalive >= KEEPALIVE_INTERVAL then
                local alive, alive_err = emit(": keepalive\n\n")
                if not alive then
                    core.log.info("MCP stream disconnected: ", alive_err)
                    break
                end
                last_keepalive = now

                local refreshed, refresh_err = session.touch(session_id)
                if not refreshed then
                    -- the marker is gone, so the message endpoint would start
                    -- rejecting this session's POSTs; close instead of pretending
                    core.log.warn("MCP session could not be refreshed: ", refresh_err)
                    break
                end
            end

            ngx_sleep(POLL_INTERVAL)
        end
    end

    session.destroy(session_id)
    return ngx_exit(0)
end


-- Both shapes follow the MCP SDK, including the -32000 code and the null id:
-- 400 when the query string carries no session, 404 when it names one the
-- gateway does not know.
local function session_error(status, message)
    return core.response.exit(status, {
        jsonrpc = "2.0",
        error = { code = -32000, message = message },
        id = core.json.null,
    })
end


-- A message body is rejected on two different grounds, with two different
-- statuses: 415 when the POST carries no content type at all, and 400 when it
-- carries one that is not JSON.
local function content_type_error(content_type)
    if type(content_type) ~= "string" or content_type == "" then
        return 415, "Unsupported Media Type: Content-Type must be application/json"
    end
    if not str_find(content_type, "application/json", 1, true) then
        return 400, "Unsupported content-type: " .. content_type
    end
    return nil
end


-- Answer a message with what the stream resolved, not with what this POST
-- resolves: the message endpoint carries only the session id, so `${...}` in
-- base_url or in a header would read empty here. A session created before this
-- was stored keeps the old behaviour rather than failing.
local function frozen_opts(opts, session_id)
    local context = session.context(session_id)
    if not context then
        return opts
    end

    local merged = core.table.clone(opts)
    if context.base_url ~= nil then
        merged.base_url = context.base_url
    end
    if context.headers ~= nil then
        merged.headers = context.headers
    end
    return merged
end


local function handle_post(ctx, opts)
    -- An empty or unparsable JSON body is a 400 even for a session nobody
    -- issued: it is rejected before the session is looked up.
    if str_find(core.request.header(ctx, "content-type") or "", "application/json", 1, true)
       and ctx._request_body_table == nil
       and core.request.get_json_request_body_table() == nil
    then
        return core.response.exit(400, { error = "invalid message body" })
    end

    local session_id = ctx.var.arg_sessionId
    if type(session_id) ~= "string" or session_id == "" then
        return session_error(400, "Missing or invalid sessionId parameter")
    end
    if not session.exists(session_id) then
        return session_error(404, "Session not found for sessionId")
    end

    local ct_status, ct_message = content_type_error(core.request.header(ctx, "content-type"))
    if ct_status then
        return session_error(ct_status, ct_message)
    end

    -- the check at the top of this function already decoded and cached this body
    local request = ctx._request_body_table
    if type(request) ~= "table" then
        local body, err = core.request.get_json_request_body_table()
        if type(body) ~= "table" then
            core.log.warn("failed to parse MCP message body: ",
                          type(err) == "table" and err.message or err)
            return core.response.exit(400, { error = "invalid message body" })
        end
        request = body
    end

    if not jsonrpc.validate(request) then
        return core.response.exit(400, jsonrpc.invalid_message())
    end

    local response = server.handle(request, frozen_opts(opts, session_id))
    if response then
        local encoded, encode_err = core.json.encode(response)
        if not encoded then
            core.log.error("failed to encode MCP response: ", encode_err)
            return core.response.exit(500)
        end

        local pushed, push_err = session.push(session_id, encoded)
        if not pushed then
            core.log.error("failed to deliver MCP response: ", push_err)
            return core.response.exit(500)
        end
    end

    -- The answer travels on the SSE stream, not in this response, so there is
    -- no body here and no content type to declare for it.
    core.response.set_header("Content-Type", nil)
    return core.response.exit(202)
end


function _M.handle(ctx, opts)
    if core.request.get_method() == "GET" then
        return handle_get(ctx, opts)
    end
    return handle_post(ctx, opts)
end


return _M
