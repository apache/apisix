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
local unpack       = unpack
local ngx          = ngx
local thread_spawn = ngx.thread.spawn
local thread_kill  = ngx.thread.kill
local resty_signal = require("resty.signal")
local core         = require("apisix.core")
local pipe         = require("ngx.pipe")

local mcp_server_wrapper  = require("apisix.plugins.mcp.server_wrapper")

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


local function on_connect(conf, ctx)
    return function(additional)
        local proc, err = pipe.spawn({conf.command, unpack(conf.args or {})})
        if not proc then
            core.log.error("failed to spawn mcp process: ", err)
            return 500
        end
        proc:set_timeouts(nil, 100, 100)
        ctx.mcp_bridge_proc = proc

        local server = additional.server

        -- ngx_pipe is a yield operation, so we no longer need
        -- to explicitly yield to other threads by ngx_sleep
        ctx.mcp_bridge_proc_event_loop = thread_spawn(function ()
            local stdout_partial, stderr_partial, need_exit
            while true do
                -- read all the messages in stdout's pipe, line by line
                -- if there is an incomplete message it is buffered and
                -- spliced before the next message
                repeat
                    local line, _
                    line, _, stdout_partial = proc:stdout_read_line()
                    if line then
                        local ok, err = server.transport:send(
                            stdout_partial and stdout_partial .. line or line
                        )
                        if not ok then
                            core.log.info("session ", server.session_id,
                                          " exit, failed to send response message: ", err)
                            need_exit = true
                            break
                        end
                        stdout_partial = nil -- luacheck: ignore
                    end
                until not line
                if need_exit then
                    break
                end

                repeat
                    local line, _
                    line, _, stderr_partial = proc:stderr_read_line()
                    if line then
                        local ok, err = server.transport:send(
                           '{"jsonrpc":"2.0","method":"notifications/stderr","params":{"content":"'
                            .. (stderr_partial and stderr_partial .. line or line) .. '"}}')
                        if not ok then
                            core.log.info("session ", server.session_id,
                                          " exit, failed to send response message: ", err)
                            need_exit = true
                            break
                        end
                        stderr_partial = "" -- luacheck: ignore
                    end
                until not line
                if need_exit then
                    break
                end
            end
        end)
    end
end


local function on_client_message(conf, ctx)
    return function(message, additional)
        core.log.info("session ", additional.server.session_id,
                      " send message to mcp server: ", additional.raw)
        ctx.mcp_bridge_proc:write(additional.raw .. "\n")
    end
end


local function on_disconnect(conf, ctx)
    return function()
        if ctx.mcp_bridge_proc_event_loop then
            thread_kill(ctx.mcp_bridge_proc_event_loop)
            ctx.mcp_bridge_proc_event_loop = nil
        end

        local proc = ctx.mcp_bridge_proc
        if proc then
            proc:shutdown("stdin")
            proc:wait()
            local _, err = proc:wait() -- check if process not exited then kill it
            if err ~= "exited" then
                proc:kill(resty_signal.signum("KILL") or 9)
            end
        end
    end
end


function _M.access(conf, ctx)
    return mcp_server_wrapper.access(conf, ctx, {
        event_handler = {
            on_connect = on_connect(conf, ctx),
            on_client_message = on_client_message(conf, ctx),
            on_disconnect = on_disconnect(conf, ctx),
        },
    })
end


return _M
