-- Copyright (C) Yuansheng Wang

local ngx_req = ngx.req
local ngx_var = ngx.var
local new_tab = require("table.new")


local _M = {version = 0.1}


function _M.get(api_ctx, name)
    local vars = api_ctx.vars
    if not vars then
        vars = new_tab(0, 8)
        api_ctx.vars = vars
    end

    local val = vars[name]
    if val then
        return val
    end

    if name == "method" then
        val = ngx_req.get_method()
    else
        val = ngx_var[name]
    end

    if val then
        vars[name] = val
    end

    return val
end


return _M
