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

--- Get the information form upstream response, or set the information to client response.
--
-- @module core.response

local tracer = require("apisix.tracer")
local encode_json = require("cjson.safe").encode
local ngx = ngx
local arg = ngx.arg
local ngx_print = ngx.print
local ngx_header = ngx.header
local ngx_add_header
if ngx.config.subsystem == "http" then
    local ngx_resp = require "ngx.resp"
    ngx_add_header = ngx_resp.add_header
end

local error = error
local select = select
local type = type
local ngx_exit = ngx.exit
local concat_tab = table.concat
local str_sub = string.sub
local tonumber = tonumber
local tostring = tostring
local clear_tab = require("table.clear")
local pairs = pairs
local ngx_var = ngx.var
local table = require("apisix.core.table")

local _M = {version = 0.1}


--- Register a callback to intercept and transform exit responses.
-- Callbacks are stored per-request in ngx.ctx and invoked by resp_exit in
-- registration order. Each callback receives (code, body, headers, conf) and
-- must return (new_code, new_body, new_headers).
--
-- @function core.response.exit_insert_callback
-- @tparam function func  Callback with signature (code, body, headers, conf).
-- @tparam any     conf   Opaque value forwarded to the callback as its last arg.
function _M.exit_insert_callback(func, conf)
    local ngx_ctx = ngx.ctx
    local exit_callback_funcs = ngx_ctx.apisix_exit_callback_funcs or {}
    table.insert_tail(exit_callback_funcs, func, conf)
    ngx_ctx.apisix_exit_callback_funcs = exit_callback_funcs
end


local resp_exit
do
    local t = {}
    local idx = 1

function resp_exit(code, ...)
    clear_tab(t)
    idx = 0

    if code and type(code) ~= "number" then
        idx = idx + 1
        t[idx] = code
        code = nil
    end

    -- When exit callbacks are registered, pass the body in its original form
    -- (table or string) so callbacks can inspect and modify it directly.
    local exit_callback_funcs = ngx.ctx.apisix_exit_callback_funcs
    if exit_callback_funcs then
        -- Extract primary body from varargs, preserving the original type.
        local body
        local nargs = select('#', ...)
        for i = 1, nargs do
            local v = select(i, ...)
            if v ~= nil then
                body = v
                break
            end
        end
        -- Include non-numeric first arg prepended before varargs, if any.
        if body == nil and idx > 0 then
            body = t[1]
        end

        local headers = {}

        for i = 1, #exit_callback_funcs, 2 do
            local callback_func = exit_callback_funcs[i]
            local callback_conf = exit_callback_funcs[i + 1]
            code, body, headers = callback_func(code, body, headers, callback_conf)
        end

        if code then
            ngx.status = code
        end
        if headers and table.nkeys(headers) > 0 then
            for k, v in pairs(headers) do
                ngx_header[k] = v
            end
        end
        if body ~= nil then
            if type(body) == "table" then
                local encoded, err = encode_json(body)
                if err then
                    error("failed to encode data: " .. err, -2)
                end
                ngx_print(encoded, "\n")
            else
                ngx_print(body)
            end
        end
        if code then
            local ctx = ngx.ctx.api_ctx
            if ctx and not ctx._resp_source then
                ctx._resp_source = "apisix"
            end
            if code >= 400 then
                tracer.finish_all(ngx.ctx, tracer.status.ERROR, "response code " .. code)
            end
            return ngx_exit(code)
        end
        return
    end

    if code then
        ngx.status = code
    end

    for i = 1, select('#', ...) do
        local v = select(i, ...)
        if type(v) == "table" then
            local body, err = encode_json(v)
            if err then
                error("failed to encode data: " .. err, -2)
            else
                idx = idx + 1
                t[idx] = body
                idx = idx + 1
                t[idx] = "\n"
            end

        elseif v ~= nil then
            idx = idx + 1
            t[idx] = v
        end
    end

    if idx > 0 then
        ngx_print(t)
    end

    if code then
        local ctx = ngx.ctx.api_ctx
        if ctx and not ctx._resp_source then
            ctx._resp_source = "apisix"
        end
        if code >= 400 then
            tracer.finish_all(ngx.ctx, tracer.status.ERROR, "response code " .. code)
        end
        return ngx_exit(code)
    end
end

end -- do
_M.exit = resp_exit


function _M.say(...)
    resp_exit(nil, ...)
end


local function set_header(append, ...)
    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    local count = select('#', ...)
    if count == 1 then
        local headers = select(1, ...)
        if type(headers) ~= "table" then
            -- response.set_header(name, nil)
            ngx_header[headers] = nil
            return
        end

        for k, v in pairs(headers) do
            if append then
                ngx_add_header(k, v)
            else
                ngx_header[k] = v
            end
        end

        return
    end

    for i = 1, count, 2 do
        if append then
            ngx_add_header(select(i, ...), select(i + 1, ...))
        else
            ngx_header[select(i, ...)] = select(i + 1, ...)
        end
    end
end


function _M.set_header(...)
    set_header(false, ...)
end

---
-- Add a header to the client response.
--
-- @function core.response.add_header
-- @usage
-- core.response.add_header("Apisix-Plugins", "no plugin")
function _M.add_header(...)
    set_header(true, ...)
end


function _M.get_upstream_status(ctx)
    -- $upstream_status maybe including multiple status, only need the last one
    return tonumber(str_sub(ctx.var.upstream_status or "", -3))
end


--- Explicitly set the response source for this request.
-- Use this in plugins that bypass NGINX proxy (e.g. ai-proxy) to indicate
-- whether the response originated from the upstream service.
-- Must be called before core.response.exit() since exit() won't override
-- an already-set source.
function _M.set_response_source(ctx, source)
    if ctx then
        ctx._resp_source = source
    end
end


--- Extract the last non-comma token from a comma/space-separated NGINX
-- upstream variable string (e.g. "-, 0.002" → "0.002", "0, 0" → "0").
-- Exported for testability; not part of the public API.
function _M.get_last_upstream_token(s)
    if not s then
        return nil
    end
    local last
    for token in s:gmatch("[^%s,]+") do
        last = token
    end
    return last
end


--- Get the source of the current response.
--
-- @function core.response.get_response_source
-- @tparam table ctx     The APISIX request context (api_ctx).
-- @treturn string One of:
--   "apisix"   — response generated by APISIX Lua code (e.g. route not found, plugin rejection)
--   "nginx"    — error generated by NGINX proxy module (e.g. connection refused, timeout)
--   "upstream" — real HTTP response returned by the upstream service
function _M.get_response_source(ctx)
    if not ctx then
        return "apisix"
    end

    -- Priority 1: explicitly marked by core.response.exit() or set_response_source()
    if ctx._resp_source then
        return ctx._resp_source
    end

    -- Priority 2: request was proxied — inspect $upstream_header_time to
    -- determine if the upstream actually sent response headers.
    --
    -- Use ngx.var directly (not ctx.var) because lua-var-nginx-module's FFI
    -- path clamps header_time from -1 to 0 via ngx_max(ms, 0), losing the
    -- "-" sentinel that NGINX uses to indicate "no response headers received"
    -- (e.g. connection refused, connect timeout).  ngx.var preserves "-".
    if ctx._apisix_proxied then
        local header_time = ngx_var.upstream_header_time
        if header_time then
            local last = _M.get_last_upstream_token(header_time)
            if last and last ~= "-" then
                ctx._resp_source = "upstream"
                return "upstream"
            end
        end
        ctx._resp_source = "nginx"
        return "nginx"
    end

    -- Fallback: never reached proxy_pass
    return "apisix"
end


function _M.clear_header_as_body_modified()
    ngx.header.content_length = nil
    -- in case of upstream content is compressed content
    ngx.header.content_encoding = nil

    -- clear cache identifier
    ngx.header.last_modified = nil
    ngx.header.etag = nil
end


-- Hold body chunks and return the final body once all chunks have been read.
-- Usage:
-- function _M.body_filter(conf, ctx)
--  local final_body = core.response.hold_body_chunk(ctx)
--  if not final_body then
--      return
--  end
--  final_body = transform(final_body)
--  ngx.arg[1] = final_body
--  ...
function _M.hold_body_chunk(ctx, hold_the_copy, max_resp_body_bytes)
    local body_buffer
    local chunk, eof = arg[1], arg[2]

    if not ctx._body_buffer then
        ctx._body_buffer = {}
    end

    if type(chunk) == "string" and chunk ~= "" then
        body_buffer = ctx._body_buffer[ctx._plugin_name]
        if not body_buffer then
            body_buffer = {
                chunk,
                n = 1
            }
            ctx._body_buffer[ctx._plugin_name] = body_buffer
            ctx._resp_body_bytes = #chunk
        else
            local n = body_buffer.n + 1
            body_buffer.n = n
            body_buffer[n] = chunk
            ctx._resp_body_bytes = ctx._resp_body_bytes + #chunk
        end
        if max_resp_body_bytes and ctx._resp_body_bytes >= max_resp_body_bytes then
            local body_data = concat_tab(body_buffer, "", 1, body_buffer.n)
            body_data = str_sub(body_data, 1, max_resp_body_bytes)
            return body_data
        end
    end

    if eof then
        body_buffer = ctx._body_buffer[ctx._plugin_name]
        if not body_buffer then
            if max_resp_body_bytes and #chunk >= max_resp_body_bytes then
                chunk = str_sub(chunk, 1, max_resp_body_bytes)
            end
            return chunk
        end

        local body_data = concat_tab(body_buffer, "", 1, body_buffer.n)
        ctx._body_buffer[ctx._plugin_name] = nil
        return body_data
    end

    if not hold_the_copy then
        -- flush the origin body chunk
        arg[1] = nil
    end
    return nil
end


return _M
