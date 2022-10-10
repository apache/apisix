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
local clear_tab = require("table.clear")
local pairs = pairs

local _M = {version = 0.1}


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
                t[idx] = body .. "\n"
            end

        elseif v ~= nil then
            idx = idx + 1
            t[idx] = v
        end
    end

    if idx > 0 then
        ngx_print(concat_tab(t, "", 1, idx))
    end

    if code then
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
function _M.hold_body_chunk(ctx, hold_the_copy)
    local body_buffer
    local chunk, eof = arg[1], arg[2]
    if type(chunk) == "string" and chunk ~= "" then
        body_buffer = ctx._body_buffer
        if not body_buffer then
            body_buffer = {
                chunk,
                n = 1
            }
            ctx._body_buffer = body_buffer
        else
            local n = body_buffer.n + 1
            body_buffer.n = n
            body_buffer[n] = chunk
        end
    end

    if eof then
        body_buffer = ctx._body_buffer
        if not body_buffer then
            return chunk
        end

        body_buffer = concat_tab(body_buffer, "", 1, body_buffer.n)
        ctx._body_buffer = nil
        return body_buffer
    end

    if not hold_the_copy then
        -- flush the origin body chunk
        arg[1] = nil
    end
    return nil
end


return _M
