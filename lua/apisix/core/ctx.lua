local log          = require("apisix.core.log")
local tablepool    = require("tablepool")
local get_var      = require("resty.ngxvar").fetch
local get_request  = require("resty.ngxvar").request
local ck           = require "resty.cookie"
local setmetatable = setmetatable
local ffi          = require("ffi")
local C            = ffi.C
local sub_str      = string.sub


ffi.cdef[[
int memcmp(const void *s1, const void *s2, size_t n);
]]


local _M = {version = 0.2}


do
    local var_methods = {
        ["method"] = ngx.req.get_method,
        ["cookie"] = function () return ck:new() end
    }

    local mt = {
        __index = function(t, name)
            local val
            local method = var_methods[name]
            if method then
                val = method()

            elseif C.memcmp(name, "cookie_", 7) == 0 then
                local cookie = t["cookie"]
                if cookie then
                    local err
                    val, err = cookie:get(sub_str(name, 8))
                    if not val then
                        log.warn("failed to fetch cookie value by name: ",
                                 name, " error: ", err)
                    end
                end

            else
                val = get_var(name, t._request)
            end

            if val ~= nil then
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
