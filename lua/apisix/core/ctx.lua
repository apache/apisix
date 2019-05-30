local tablepool = require("tablepool")
local get_var = require("resty.ngxvar").fetch
local get_request = require("resty.ngxvar").request
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
                val = get_var(name, t._request)
            end

            if val then
                t[name] = val
            end

            return val
        end
    }

function _M.set_vars_meta(ctx)
    local var = tablepool.fetch("ctx_var", 0, 32)
    var._request = get_request()
    setmetatable(var, mt)
    ctx.var = var
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    tablepool.release("ctx_var", ctx.var)
    ctx.var = nil
end

end -- do


return _M
