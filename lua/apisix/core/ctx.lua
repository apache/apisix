local new_tab = require("table.new")
local ngx_var = ngx.var
local setmetatable = setmetatable


local _M = {version = 0.1}


do
    local var_methods = {
        ["method"] = ngx.req.get_method
    }

    local mt = {
        __index = function(t, name)
            local val
            local method = var_methods[name]
            if method then
                val = method()

            else
                val = ngx_var[name]
            end

            if val then
                t[name] = val
            end

            return val
        end
    }

function _M.set_vars_meta(ctx)
    ctx.var = new_tab(0, 32)
    setmetatable(ctx.var, mt)
end

end -- do


return _M
