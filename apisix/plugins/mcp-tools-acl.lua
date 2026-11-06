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

local core              = require("apisix.core")
local sse               = require("apisix.plugins.ai-transport.sse")
local expr              = require("resty.expr.v1")
local ngx               = ngx
local ngx_arg           = ngx.arg
local ipairs            = ipairs
local str_find          = string.find
local str_byte          = string.byte
local type              = type
local setmetatable      = setmetatable
local table             = table

local lrucache = core.lrucache.new({
    type = "plugin",
})

local rules_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            allow_tools = {
                type = "array",
                items = { type = "string", minLength = 1 },
                description = "Allowed MCP tool names (exact match, case-sensitive). " ..
                              "Empty array denies all tools.",
            },
            deny_tools = {
                type = "array",
                items = { type = "string", minLength = 1 },
                description = "Denied MCP tool names (exact match, case-sensitive).",
            },
            rejected_code = {
                type = "integer",
                minimum = 200,
                maximum = 599,
                default = 403,
                description = "HTTP status code returned when a tool is denied (default 403).",
            },
            rejected_msg = {
                type = "string",
                minLength = 1,
                description = "Message included in the response body when a tool is denied."
            },
            expr = {
                type = "array",
                description = "an array of variable expressions; " ..
                              "MCP tools are filtered only when all expressions evaluate to true",
            },
        },
        oneOf = {
            {required = {"allow_tools"}},
            {required = {"deny_tools"}},
        },
    },
    minItems = 1,
}

local schema = {
    type = "object",
    properties = {
        rules = rules_schema,
        max_resp_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum response body size in bytes buffered into "
                       .. "memory for tool filtering; larger responses are "
                       .. "truncated",
        },
    },
    required = {"rules"},
}

local _M = {
    version  = 0.1,
    priority = 539,
    name     = "mcp-tools-acl",
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, item in ipairs(conf.rules) do
        if item.expr then
            local vars_ok, vars_err = expr.new(item.expr)
            if not vars_ok then
                return false, "failed to validate the 'expr' expression: " .. vars_err
            end
        end
    end

    return true
end


local function is_tool_in_list(tools, tool_name)
    for _, name in ipairs(tools) do
        if name == tool_name then
            return true
        end
    end
    return false
end


local function reject(conf)
    local code = conf.rejected_code or 403
    local msg  = conf.rejected_msg  or "MCP tool is not allowed"
    return code, { message = msg }
end


-- Parse the request body as JSON and enforce the given conf's allow/deny rules.
-- Sets ctx.mcp_tools_acl_filter for tools/list,
-- and returns a rejection response for disallowed tools/call requests.
-- Returns nil on pass-through, or (code, body) to short-circuit.
-- data is the already-decoded JSON-RPC request table.
local function enforce(conf, ctx, data)
    local method = data.method
    if not method then
        return
    end

    if method == "tools/list" then
        -- Mark this request for response filtering in body_filter.
        ctx.mcp_tools_acl_filter = true

    elseif method == "tools/call" then
        local params = data.params
        if type(params) ~= "table" or type(params.name) ~= "string" then
            return 400, { message = "Invalid MCP tools/call request" }
        end

        if conf.deny_tools and is_tool_in_list(conf.deny_tools, params.name) then
            return reject(conf)
        end

        if conf.allow_tools and not is_tool_in_list(conf.allow_tools, params.name) then
            return reject(conf)
        end

    -- else: other MCP methods (initialize, ping, etc.) — pass through unchanged.
    end
end


-- Compiles the expr field of each conf item into a resty.expr object.
-- Items without an expr field are stored as false (unconditional match).
-- Returns the compiled exprs array, or nil + err on failure.
local function create_exprs(conf)
    local exprs = {}
    for index, item in ipairs(conf) do
        if item.expr then
            local e, err = expr.new(item.expr)
            if not e then
                return nil, "failed to create expression for rule #" .. index .. ": "
                            .. (err or "unknown error")
            end
            core.table.insert(exprs, e)
        else
            core.table.insert(exprs, false)
        end
    end
    return exprs
end


local function match(exprs, conf, ctx)
    for index, item in ipairs(conf) do
        local e = exprs[index]
        if not e then
            -- no expr on this item: always matches
            return item
        end
        local matched, err = e:eval(ctx.var)
        if err then
            core.log.error("mcp-tools-acl: failed to evaluate expr for rule #", index,
                           ": ", err)
            return nil, err
        end
        if matched then
            return item
        end
    end
    return nil
end


function _M.access(conf, ctx)
    -- openapi-to-mcp (priority 540) sets ctx.openapi_to_mcp_active = true
    -- during its access() phase as a coordination signal.
    if not ctx.openapi_to_mcp_active then
        core.log.warn("mcp-tools-acl: openapi-to-mcp plugin is not active on this route, " ..
                      "skipping enforcement")
        return
    end

    if not ctx.consumer then
        return
    end

    local exprs, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_exprs, conf.rules)
    if not exprs then
        core.log.error("failed to create expressions: ", err)
        return 500
    end

    local matched, match_err = match(exprs, conf.rules, ctx)
    if match_err then
        -- Expression evaluation failed; fail closed to avoid bypassing ACL.
        return 500
    end
    if not matched then
        -- No rule matched (all items have expr and none evaluated true); skip ACL.
        return
    end

    -- Store the matched rule item so body_filter can use it for response filtering.
    ctx.mcp_tools_acl_conf = matched

    -- SSE transport GET /sse: the long-lived connection that carries tool list responses.
    -- key-auth (or any other auth plugin) runs before this plugin at its higher priority,
    -- so ctx.consumer and conf are already correctly merged from the consumer's config.
    -- We simply mark the context to enable SSE stream filtering in body_filter.
    -- There is no request body to inspect on a GET; tools/call enforcement is handled
    -- on the companion POST requests.
    if core.request.get_method() == "GET" then
        ctx.mcp_tools_acl_filter = true
        return
    end

    -- get_json_request_body_table() hits ctx._request_body_table when
    -- openapi-to-mcp (priority 540) already decoded the body in its access phase.
    local data, err = core.request.get_json_request_body_table()
    if err then
        core.log.warn("mcp-tools-acl: failed to get request body: ", err.message)
        return
    end
    if type(data) ~= "table" then
        return
    end

    return enforce(matched, ctx, data)
end


function _M.header_filter(conf, ctx)
    if not ctx.mcp_tools_acl_filter then
        return
    end
    -- Nil out Content-Length / Content-Encoding so nginx does not send
    -- the original length after we rewrite the body in body_filter.
    core.response.clear_header_as_body_modified()
end


local function filter_tools_in_json(body, allow_tools, deny_tools)
    local data, err = core.json.decode(body)
    if not data or type(data) ~= "table" then
        core.log.info("mcp-tools-acl: failed to decode response body: ", err)
        return body
    end

    local result = data.result
    if not result or type(result.tools) ~= "table" then
        return body
    end

    local filtered = setmetatable({}, core.json.array_mt)
    for _, tool in ipairs(result.tools) do
        if type(tool) == "table"
            and type(tool.name) == "string"
            then
            if not (deny_tools and is_tool_in_list(deny_tools, tool.name))
                and (not allow_tools or is_tool_in_list(allow_tools, tool.name)) then
                filtered[#filtered + 1] = tool
            end
        end
    end
    result.tools = filtered

    local new_body, encode_err = core.json.encode(data)
    if not new_body then
        core.log.warn("mcp-tools-acl: failed to encode filtered body: ", encode_err)
        return body
    end

    return new_body
end


local _SSE_BUF_LIMIT = 1024 * 1024  -- 1 MB guard against oversized incomplete events
local LBRACE = string.byte("{")

local function decode_and_filter(raw, allow_tools, deny_tools)
    local events = sse.decode(raw)
    if #events == 0 then
        return nil
    end

    local out = {}
    for _, event in ipairs(events) do
        local data = event.data
        if data and data ~= "" and str_byte(data, 1) == LBRACE then
            event.data = filter_tools_in_json(data, allow_tools, deny_tools)
        end
        out[#out + 1] = sse.encode(event)
    end
    return table.concat(out)
end


local function filter_sse_events(chunk, allow_tools, deny_tools, ctx)
    if ctx._mcp_sse_passthrough then
        return chunk
    end

    local prev_buf = ctx._mcp_sse_buf or ""
    local buf = prev_buf .. chunk

    local complete, remainder = sse.split_buf(buf)

    if #remainder > _SSE_BUF_LIMIT then
        core.log.warn("mcp-tools-acl: SSE remainder exceeded 1 MB limit, ",
                      "passing through unfiltered")
        ctx._mcp_sse_buf = nil
        ctx._mcp_sse_passthrough = true
        return buf
    end

    ctx._mcp_sse_buf = remainder ~= "" and remainder or nil

    if complete == "" then
        return ""
    end

    return decode_and_filter(complete, allow_tools, deny_tools) or ""
end


function _M.body_filter(conf, ctx)
    if not ctx.mcp_tools_acl_filter then
        return
    end

    local acl_conf = ctx.mcp_tools_acl_conf
    local allow_tools = acl_conf and acl_conf.allow_tools
    local deny_tools  = acl_conf and acl_conf.deny_tools

    local content_type = ngx.header["Content-Type"] or ""

    if str_find(content_type, "text/event-stream", 1, true) then
        local chunk = ngx_arg[1]
        local eof   = ngx_arg[2]

        if chunk and chunk ~= "" then
            ngx_arg[1] = filter_sse_events(chunk, allow_tools, deny_tools, ctx)
        end

        if eof and ctx._mcp_sse_buf and ctx._mcp_sse_buf ~= "" then
            local remainder = ctx._mcp_sse_buf
            ctx._mcp_sse_buf = nil
            local filtered = decode_and_filter(remainder, allow_tools, deny_tools)
            ngx_arg[1] = (ngx_arg[1] or "") .. (filtered or remainder)
        end

        return
    end

    if str_find(content_type, "application/json", 1, true) then
        -- Single-body response: buffer the whole body, then filter.
        local body = core.response.hold_body_chunk(ctx, false, conf.max_resp_body_size)
        if not body then
            return
        end
        ngx_arg[1] = filter_tools_in_json(body, allow_tools, deny_tools)
        ngx_arg[2] = true
        return
    end

    -- Unknown content type: pass through unchanged.
end


return _M
