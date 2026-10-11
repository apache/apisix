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
local core        = require("apisix.core")
local streamable_http = require("apisix.plugins.openapi-to-mcp.transport.streamable_http")
local mcp_sse         = require("apisix.plugins.openapi-to-mcp.transport.sse")
local ngx         = ngx
local pairs       = pairs

local schema = {
    type = "object",
    properties = {
        transport = {
            description = "The transport mechanisms for client-server communication",
            type = "string",
            default = "sse",
            enum = {"sse", "streamable_http"},
        },
        openapi_url = {
            description = "URL of the OpenAPI specification document",
            type = "string",
            minLength = 1,
        },
        base_url = {
            description = "Base URL of the external service",
            type = "string",
            minLength = 1,
        },
        headers = {
            description = "Headers to include in requests to the external service",
            type = "object",
            minProperties = 0,
            patternProperties = {
                ["^[^:]+$"] = {
                    oneOf = {
                        { type = "string" }
                    }
                }
            },
        },
        flatten_parameters = {
            description = "Whether to flatten query and path parameters " ..
            "in the tool inputSchema. When false (default), " ..
            "parameters are nested under queryParameters or pathParameters. " ..
            "When true, parameters are placed directly in properties.",
            type = "boolean",
            default = false,
        },
    },
    required = { "openapi_url", "base_url" },
}

local plugin_name = "openapi-to-mcp"

local _M = {
    version  = 0.1,
    priority = 540,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Resolve base_url and headers against request variables.
local function resolve_conf(conf, ctx)
    local base_url, err = core.utils.resolve_var(conf.base_url, ctx.var)
    if err then
        core.log.error("failed to resolve variable for base_url: ",
                       conf.base_url, ", error: ", err)
        base_url = conf.base_url
    end

    local headers = {}
    for key, value in pairs(conf.headers or {}) do
        local resolved_value, herr = core.utils.resolve_var(value, ctx.var)
        if herr then
            core.log.error("failed to resolve variable for header, key: ", key,
                           ", error: ", herr)
            resolved_value = value
        end
        headers[key] = resolved_value
    end

    return base_url, headers
end


function _M.access(conf, ctx)
    if conf.transport == "streamable_http" then
        local base_url, headers = resolve_conf(conf, ctx)

        -- Defer the answer to before_proxy. Exiting here would skip every
        -- plugin with a lower priority that still has to run in access, such
        -- as an authorization check on the tool being called.
        ctx.mcp_inprocess_opts = {
            conf = conf,
            base_url = base_url,
            headers = headers,
            transport = "streamable_http",
        }
        -- The answer is produced in before_proxy, so the request never reaches
        -- an upstream; handle_upstream() runs before_proxy and returns.
        ctx.bypass_nginx_upstream = true
        return
    end

    if conf.transport ~= "sse" then
        core.log.error("Invalid MCP transport: ", conf.transport)
        return 500, { message = "Invalid MCP transport"}
    end

    local base_url, headers = resolve_conf(conf, ctx)

    -- The client is told to POST its messages to the path the route matched.
    local message_path = ctx.curr_req_matched and ctx.curr_req_matched._path

    ngx.ctx.disable_proxy_buffering = true
    ctx.mcp_inprocess_opts = {
        conf = conf,
        base_url = base_url,
        headers = headers,
        transport = "sse",
        message_path = message_path,
    }
    ctx.bypass_nginx_upstream = true
end


function _M.before_proxy(conf, ctx)
    local opts = ctx.mcp_inprocess_opts
    if not opts then
        return
    end

    -- Every body the transports produce is JSON, and core.response.exit() sets
    -- no content type of its own, so without this they would all go out as
    -- text/plain. Set once here so no rejection path can miss it; the two that
    -- stream override it with text/event-stream on their way out.
    core.response.set_header("Content-Type", "application/json")

    if opts.transport == "sse" then
        return mcp_sse.handle(ctx, opts)
    end
    return streamable_http.handle(ctx, opts)
end


return _M
