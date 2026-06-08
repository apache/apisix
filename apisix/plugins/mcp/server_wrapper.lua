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
local ngx          = ngx
local ngx_exit     = ngx.exit
local ngx_on_abort = ngx.on_abort
local re_match     = ngx.re.match
local pcall        = pcall
local core         = require("apisix.core")
local mcp_server   = require("apisix.plugins.mcp.server")
local session_limit = require("apisix.plugins.mcp.session_limit")

local _M = {}

local V241105_ENDPOINT_SSE     = "sse"
local V241105_ENDPOINT_MESSAGE = "message"

local DEFAULT_MAX_SESSIONS     = 100


-- run the SSE session loop; only returns once the client disconnects (or the
-- connection setup fails). kept separate so that the caller can always release
-- the resources it reserved, even if the loop raises.
local function run_session(conf, opts, server)
    -- send SSE headers and first chunk
    core.response.set_header("Content-Type", "text/event-stream")
    core.response.set_header("Cache-Control", "no-cache")

    -- stop the session as soon as the client goes away rather than waiting for
    -- the next keepalive write to fail, so the backend process is released
    -- promptly. requires lua_check_client_abort to be enabled; degrade to the
    -- write-failure path if it is not.
    local ok, err = ngx_on_abort(function()
        server:stop()
    end)
    if not ok then
        core.log.warn("failed to register client abort handler: ", err)
    end

    -- send endpoint event to advertise the message endpoint
    server.transport:send(conf.base_uri .. "/message?sessionId=" .. server.session_id, "endpoint")

    if opts.event_handler and opts.event_handler.on_client_message then
        server:on(mcp_server.EVENT_CLIENT_MESSAGE, function(message, additional)
            additional.server = server
            opts.event_handler.on_client_message(message, additional)
        end)
    end

    if opts.event_handler and opts.event_handler.on_connect then
        local code, body = opts.event_handler.on_connect({ server = server })
        if code then
            return code, body
        end
        server:start() -- this is a sync call that only returns when the client disconnects
    end
end


local function sse_handler(conf, ctx, opts)
    local server = opts.server

    -- bound the number of concurrent sessions a worker will keep open, so a
    -- route cannot be driven to spawn an unbounded number of backend processes
    local max_sessions = conf.max_sessions or DEFAULT_MAX_SESSIONS
    if not session_limit.acquire(max_sessions) then
        core.log.warn("mcp session limit reached (", max_sessions,
                      "), rejecting new SSE connection")
        return core.response.exit(429,
            { error_msg = "too many concurrent MCP sessions" })
    end

    local ok, code, body = pcall(run_session, conf, opts, server)

    -- always release: tear down the backend process/broker state and free the
    -- session slot regardless of how the loop ended. the teardown is itself
    -- guarded so that a raising handler cannot skip session_limit.release() and
    -- pin the worker at the ceiling.
    local cleanup_ok, cleanup_err = pcall(function()
        if opts.event_handler and opts.event_handler.on_disconnect then
            opts.event_handler.on_disconnect({ server = server })
        end
        server:close()
    end)
    session_limit.release()
    if not cleanup_ok then
        core.log.error("mcp session cleanup error: ", cleanup_err)
    end

    if not ok then
        core.log.error("mcp session handler error: ", code)
        return core.response.exit(500)
    end

    if code then
        return code, body
    end

    ngx_exit(0) -- exit current phase, skip the upstream module
end


local function message_handler(conf, ctx, opts)
    local body = core.request.get_body(nil, ctx)
    if not body then
        return 400
    end

    local ok, err = opts.server:push_message(body)
    if not ok then
        core.log.error("failed to add task to queue: ", err)
        return 500
    end

    return 202
end


function _M.access(conf, ctx, opts)
    local m, err = re_match(ctx.var.uri, "^" .. conf.base_uri .. "/(.*)", "jo")
    if err then
        core.log.info("failed to mcp base uri: ", err)
        return core.response.exit(404)
    end
    local action = m and m[1] or false
    if not action then
        return core.response.exit(404)
    end

    if action == V241105_ENDPOINT_SSE and core.request.get_method() == "GET" then
        opts.server = mcp_server.new({})
        return sse_handler(conf, ctx, opts)
    end

    if action == V241105_ENDPOINT_MESSAGE and core.request.get_method() == "POST" then
        -- TODO: check ctx.var.arg_sessionId
        -- recover server instead of create
        opts.server = mcp_server.new({ session_id = ctx.var.arg_sessionId })
        return core.response.exit(message_handler(conf, ctx, opts))
    end

    return core.response.exit(404)
end


return _M
