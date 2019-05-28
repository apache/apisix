-- Copyright (C) Yuansheng Wang

local ngx = ngx
local get_headers = ngx.req.get_headers


local _M = {version = 0.1}


local function _headers(ctx)
    local headers = ctx.headers
    if not headers then
        headers = get_headers()
        ctx.headers = headers
    end

    return headers
end
_M.headers = _headers


function _M.header(ctx, name)
    return _headers(ctx)[name]
end


return _M
