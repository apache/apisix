-- Copyright (C) Yuansheng Wang

local ngx = ngx
local get_headers = ngx.req.get_headers
local tonumber = tonumber
local error    = error
local type     = type
local str_fmt  = string.format

local _M = {version = 0.1}


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


return _M
