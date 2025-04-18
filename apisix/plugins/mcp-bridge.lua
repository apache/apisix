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
local re_match     = ngx.re.match
local resty_signal = require("resty.signal")
local core         = require("apisix.core")
local pipe         = require("ngx.pipe")

local mcp_session_manager = require("apisix.plugins.mcp.session")

local V241105_ENDPOINT_SSE     = "sse"
local V241105_ENDPOINT_MESSAGE = "message"

local schema = {
    type = "object",
    properties = {
        base_uri = {
            type = "string",
            minLength = 1,
            default = "",
        },
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
    },
    required = {
        "command"
    },
}

local plugin_name = "mcp-bridge"

local _M = {
    version = 0.1,
    priority = 510,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end


local function sse_send(id, event, data)
    local ok, err = ngx.print((id and "id: " .. id .. "\n" or "") ..
                              "event: " .. event .. "\ndata: " .. data .. "\n\n")
    if not ok then
        return ok, "failed to write buffer: " .. err
    end
    return ngx.flush(true)
end


local function sse_handler(conf, ctx)
    -- TODO: recover by Last-Event-ID
    local session = mcp_session_manager.new()

    -- spawn subprocess
    local proc, err = pipe.spawn({conf.command, unpack(conf.args or {})})
    if not proc then
        core.log.error("failed to spawn mcp process: ", err)
        return 500
    end
    proc:set_timeouts(nil, 100, 100)

    core.response.set_header("Content-Type", "text/event-stream")
    core.response.set_header("Cache-Control", "no-cache")

    -- send endpoint event to advertise the message endpoint
    sse_send(nil, "endpoint", conf.base_uri .. "/message?sessionId=" .. session.id) --TODO assume or configured

    local stdout_partial, stderr_partial

    -- enter loop
    while true do
        if session:session_need_ping() then
            local next_ping_id, err = session:session_next_ping_id()
            if not next_ping_id then
                core.log.error("session ", session.id, " exit, failed to get next ping id: ", err)
                break
            end
            local ok, err = sse_send(nil, "message", '{"jsonrpc": "2.0","method": "ping","id":"ping:'..next_ping_id..'"}')
            if not ok then
                core.log.info("session ", session.id, " exit, failed to send ping message: ", err)
                break
            end
        end
        if session:session_timed_out() then
            core.log.info("session ", session.id, " exit, timed out")
            break
        end

        -- pop the message from client in the queue and send it to the mcp server
        repeat
            local queue_item, err = session:pop_message_queue()
            if err then
                core.log.info("session ", session.id, " exit, failed to pop message from queue: ", err)
                break
            end
            -- write task message to stdio
            if queue_item and type(queue_item) == "string" then
                core.log.info("session ", session.id, " send message to mcp server: ", queue_item)
                proc:write(queue_item .. "\n")
            end
        until not queue_item

        -- read all the messages in stdout's pipe, line by line
        -- if there is an incomplete message it is buffered and spliced before the next message
        repeat
            local line, _
            line, _, stdout_partial = proc:stdout_read_line()
            if line then
                local ok, err = sse_send(nil, "message", stdout_partial and stdout_partial .. line or line)
                if not ok then
                    core.log.info("session ", session.id, " exit, failed to send response message: ", err)
                    break
                end
                stdout_partial = nil
            end
        until not line

        repeat
            local line, _
            line, _, stderr_partial = proc:stderr_read_line()
            if line then
                local ok, err = sse_send(nil, "message",
                    '{"jsonrpc":"2.0","method":"notifications/stderr","params":{"content":"'
                    .. (stderr_partial and stderr_partial .. line or line) .. '"}}'
                )
                if not ok then
                    core.log.info("session ", session.id, " exit, failed to send response message: ", err)
                    break
                end
                stderr_partial = ""
            end
        until not line
    end

    session:destroy()

    -- shutdown the subprocess
    proc:shutdown("stdin")
    proc:wait()
    local _, err = proc:wait() -- check if process not exited then kill it
    if err ~= "exited" then
        proc:kill(resty_signal.signum("KILL") or 9)
    end
end


local function message_handler(conf, ctx)
    local session_id = ctx.var.arg_sessionId
    local session, err = mcp_session_manager.recover(session_id)

    if not session then
        core.log.error("failed to recover session: ", err)
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
        session:on_session_pong()
        return 202
    end

    local ok, err = session:push_message_queue(body)
    if not ok then
        core.log.error("failed to add task to queue: ", err)
        return 500
    end

    return 202
end


function _M.access(conf, ctx)
    local m, err = re_match(ctx.var.uri, "^" .. conf.base_uri .. "/(.*)", "jo")
    if err then
        core.log.info("failed to mcp base uri: ", err)
        return 404
    end
    local action = m and m[1] or false
    if not action then
        return 404
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
