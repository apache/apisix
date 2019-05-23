-- Copyright (C) Yuansheng Wang

local ngx = ngx
local get_headers = ngx.req.get_headers
local ngx_var = ngx.var
local new_tab = require("table.new")
local var_methods = {
    -- todo: support more type
    method = ngx.req.get_method
}


local _M = {version = 0.1}


function _M.header(ctx, name)
    local headers = ctx.headers
    if not headers then
        headers = get_headers()
        ctx.headers = headers
    end

    return ctx.headers[name]
end


function _M.var(ctx, name)
    local vars = ctx.vars
    if not vars then
        vars = new_tab(0, 8)
        ctx.vars = vars
    end

    local val = vars[name]
    if val then
        return val
    end

    -- todo: support more data type
    local method = var_methods[name]
    if method then
        val = method()
    else
        val = ngx_var[name]
    end

    if val then
        vars[name] = val
    end

    return val
end


return _M
