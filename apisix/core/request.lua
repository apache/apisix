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

local lfs = require("lfs")
local ngx = ngx
local get_headers = ngx.req.get_headers
local tonumber = tonumber
local error    = error
local type     = type
local str_fmt  = string.format
local io_open  = io.open
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local req_get_body_file = ngx.req.get_body_file


local _M = {}


local function _headers(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    local headers = ctx.headers
    if not headers then
        headers = get_headers()
        ctx.headers = headers
    end

    return headers
end

local function _validate_header_name(name)
    local tname = type(name)
    if tname ~= "string" then
        return nil, str_fmt("invalid header name %q: got %s, " ..
                "expected string", name, tname)
    end

    return name
end

_M.headers = _headers


function _M.header(ctx, name)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return _headers(ctx)[name]
end


function _M.set_header(header_name, header_value)
    local err
    header_name, err = _validate_header_name(header_name)
    if err then
        error(err)
    end
    ngx.req.set_header(header_name, header_value)
end


-- return the remote address of client which directly connecting to APISIX.
-- so if there is a load balancer between downstream client and APISIX,
-- this function will return the ip of load balancer.
function _M.get_ip(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return ctx.var.realip_remote_addr or ctx.var.remote_addr or ''
end


-- get remote address of downstream client,
-- in cases there is a load balancer between downstream client and APISIX.
function _M.get_remote_client_ip(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return ctx.var.remote_addr or ''
end


function _M.get_remote_client_port(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return tonumber(ctx.var.remote_port)
end


local function get_file(file_name)
    local f, err = io_open(file_name, 'r')
    if not f then
        return nil, err
    end

    local req_body = f:read("*all")
    f:close()
    return req_body
end


function _M.get_body(max_size)
    req_read_body()

    local req_body = req_get_body_data()
    if req_body then
        return req_body
    end

    local file_name = req_get_body_file()
    if not file_name then
        return nil
    end

    if max_size then
        local size, err = lfs.attributes (file_name, "size")
        if not size then
            return nil, err
        end

        if size > max_size then
            return nil, "request size " .. size .. " is greater than the "
                        .. "maximum size " .. max_size .. " allowed"
        end
    end

    local req_body, err = get_file(file_name)
    return req_body, err
end


function _M.get_scheme(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return ctx.var.scheme or ''
end


function _M.get_host(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return ctx.var.host or ''
end


function _M.get_port(ctx)
    if not ctx then
        ctx = ngx.ctx.api_ctx
    end
    return tonumber(ctx.var.server_port)
end


function _M.get_http_version()
    return ngx.req.http_version()
end

return _M
