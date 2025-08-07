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

local core = require("apisix.core")
local plugin = require("apisix.plugin")

local plugin_name = "sse"

local schema = {
    type = "object",
    properties = {
        proxy_read_timeout = {
            type = "integer",
            description = "Sets the timeout for reading a response from the proxied server, in seconds. A value of 0 turns off this timeout.",
            default = 3600, -- 1 hour
            minimum = 0,
        },
        override_content_type = {
            type = "boolean",
            description = "Whether to force the Content-Type header to 'text/event-stream'.",
            default = true,
        },
        connection_header = {
            type = "string",
            enum = { "keep-alive", "close" },
            description = "Value for the 'Connection' response header.",
            default = "keep-alive",
        },
        cache_control = {
            type = "string",
            description = "Value for the 'Cache-Control' response header.",
            default = "no-cache",
        }
    },
}

local _M = {
    version = 0.1,
    priority = 1005, -- Runs after authentication but before most other plugins.
    name = plugin_name,
    schema = schema,
    stream_only = false,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- The rewrite phase is executed before the request is forwarded to the upstream.
-- This is the correct place to set Nginx variables that control proxy behavior.
function _M.rewrite(conf, ctx)
    core.log.debug("sse plugin rewrite phase")

    -- Disable response buffering from the proxied server.
    -- This is the key to making SSE work, as it allows data to be sent
    -- to the client as soon as it's received from the upstream.
    core.ctx.set_var(ctx, "proxy_buffering", "off")
    core.log.debug("sse plugin set proxy_buffering to off")

    -- Also disable request buffering. While not strictly required for SSE
    -- (which is server-to-client), it's good practice for streaming APIs.
    core.ctx.set_var(ctx, "proxy_request_buffering", "off")
    core.log.debug("sse plugin set proxy_request_buffering to off")

    -- Set a long read timeout, as SSE connections are long-lived.
    -- The default is 60s, which would prematurely close the connection.
    local timeout_str = conf.proxy_read_timeout .. "s"
    core.ctx.set_var(ctx, "proxy_read_timeout", timeout_str)
    core.log.debug("sse plugin set proxy_read_timeout to ", timeout_str)
end

-- The header_filter phase is executed after the response headers are received
-- from the upstream and before they are sent to the client.
function _M.header_filter(conf, ctx)
    core.log.debug("sse plugin header_filter phase")

    core.response.set_header("X-Accel-Buffering", "no")
    core.log.debug("sse plugin set X-Accel-Buffering to no")
    core.response.set_header("Cache-Control", conf.cache_control)
    core.log.debug("sse plugin set Cache-Control to ", conf.cache_control)
    core.response.set_header("Connection", conf.connection_header)
    core.log.debug("sse plugin set Connection to ", conf.connection_header)

    if conf.override_content_type then
        core.response.set_header("Content-Type", "text/event-stream; charset=utf-8")
        core.log.debug("sse plugin set Content-Type to text/event-stream; charset=utf-8")
    end
end

return _M