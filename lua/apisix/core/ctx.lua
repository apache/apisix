-- Copyright (C) Yuansheng Wang

local ngx_var = ngx.var
local new_tab = require("table.new")


local _M = {version = 0.1}


local var_methods = {
    -- todo: support more type
    method = ngx.req.get_method
}


function _M.get_var(api_ctx, name)
    local vars = api_ctx.vars
    if not vars then
        vars = new_tab(0, 8)
        api_ctx.vars = vars
    end

    local val = vars[name]
    if val then
        return val
    end

    -- todo: added more data type
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
