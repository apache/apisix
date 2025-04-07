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
local table_remove = table.remove
local ngx = ngx
local resty_signal = require("resty.signal")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local upstream = require("apisix.upstream")
local pipe = require("ngx.pipe")
local mcp_session_manager = require("apisix.plugins.mcp.session")

local V241105_ENDPOINT_SSE = "sse"
local V241105_ENDPOINT_MESSAGE = "message"

local schema = {
    type = "object",
    properties = {
        command = {
            type = "string",
            minLength = 1,
        },
        args = {
            type = "array",
            items = {
                type = "string",
            },
            minItems = 0,
        },
        ping_interval = {
            type = "integer",
            minimum = 1,
            default = 30000,
        },
        session_inactive_timeout = {
            type = "integer",
            minimum = 1,
            default = 60000,
        },
    },
    required = {
        "command"
    },
}

local plugin_name = "mcp-bridge"

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end


local function sse_send(id, event, data)
    if id then
        ngx.say("id: " .. id)
    end
    if event then
        ngx.say("event: " .. event)
    end
    local ok, err = ngx.print("data: " .. data .. "\n\n")
    if not ok then
        ngx.log(ngx.ERR, "failed to send SSE data to buffer: ", err)
        return nil, err
    end
    return ngx.flush(true)
end


local function sse_handler(conf, ctx)
    -- TODO: recover by Last-Event-ID
    local session = mcp_session_manager.new()

    core.response.set_header("Content-Type", "text/event-stream")
    core.response.set_header("Cache-Control", "no-cache")

    -- spawn subprocess
    local proc, err = pipe.spawn({conf.command, unpack(conf.args or {})})
    if not proc then
        ngx.log(ngx.ERR, "failed to spawn mcp process: ", err)
        return 500
    end

    -- send endpoint event to advertise the message endpoint
    sse_send(nil, "endpoint", "/mcp/message?sessionId=" .. session.id .. "")

    -- enter loop
    while true do
        session = mcp_session_manager.recover(session.id)
        if not session then
            ngx.log(ngx.ERR, "failed to recover session in loop: ", err)
            return 500 --TODO throw error by SSE
        end

        local queue_item_str, queue_item
        local skip_response
        local result

        if session.last_active_at + 30 < ngx.time() then
            session.ping_id = session.ping_id + 1
            local ok, err = sse_send(nil, "message", '{"jsonrpc": "2.0","method": "ping","id":"ping:'..session.ping_id..'"}')
            if not ok then
                core.log.info("session ", session.id, " exit, failed to send ping message: ", err)
                break
            end
        end
        if session.last_active_at + 60 < ngx.time() then
            core.log.info("session ", session.id, " exit, inactive timeout")
            break
        end

        queue_item_str, err = session:pop_message_queue()
        if not queue_item_str then
            if err then
                core.log.error("session ", session.id, " exit, failed to pop message from queue: ", err)
                break
            end
            goto CONTINUE
        end
        queue_item = core.json.decode(queue_item_str)

        -- According to the JSON-RPC specification, if the message does not contain an id,
        -- it means that it is a notification message from peer and the server does not
        -- need to respond to it
        skip_response = queue_item.id == nil

        -- write task to stdio and read result
        proc:write(queue_item_str .. "\n")
        if not skip_response then
            result = proc:stdout_read_line() --TODO: read all
            core.log.error("session ", session.id, " message from stdout, ", result)
        end

        -- flush queue modification to storage
        session:flush_to_storage()

        if result and not skip_response then
            local ok = sse_send(nil, "message", result)
            if not ok then
                core.log.info("session ", session.id, " exit, failed to send response message: ", err)
                break
            end
        end

        ::CONTINUE::
        queue_item_str = nil
        queue_item = nil
        skip_response = false
        result = nil
        ngx.sleep(1)
    end

    session:destroy()

    -- close the subprocess
    proc:shutdown("stdin")
    proc:wait()
    local _, err = proc:wait() -- check if process not exited then kill it
    if err ~= "exited" then
        proc:kill(resty_signal.signum("KILL"))
    end
end


local function message_handler(conf, ctx)
    local session_id = ctx.var.arg_sessionId
    --ngx.log(ngx.ERR, 'sessionId: ', session_id)
    local session = mcp_session_manager.recover(session_id)

    if not session then
        return 404
    end

    local body = core.request.get_body(nil, ctx)
    if not body then
        return 400
    end

    local body_json = core.json.decode(body)
    if not body_json then
        return 400
    end
    if core.string.has_prefix(tostring(body_json.id), "ping") then --TODO check client pong
        session:session_pong()
        return 202
    end

    local ok, err = session:push_message_queue(body)
    if not ok then
        ngx.log(ngx.ERR, "failed to add task to queue: ", err)
        return 500
    end

    return 202
end


function _M.access(conf, ctx)
    local action = ctx.var.uri_param_action
    if not action then
        return 404
    end

    if core.request.get_method() == "OPTIONS" then
        return 200
    end

    if action == V241105_ENDPOINT_SSE and core.request.get_method() == "GET" then
        return sse_handler(conf, ctx)
    end

    if action == V241105_ENDPOINT_MESSAGE and core.request.get_method() == "POST" then
        return message_handler(conf, ctx)
    end

    return 200
end


return _M
