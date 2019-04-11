-- Copyright (C) Yuansheng Wang

local log = require("apimeta.comm.log")
local resp = require("apimeta.comm.resp")
local route_handler = require("apimeta.route.handler")
local ngx_req = ngx.req

local _M = {}

function _M.init()

end

function _M.init_worker()
    require("apimeta.route.load").init_worker()
end

function _M.access()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = {}
        ngx_ctx.api_ctx = api_ctx
    end

    api_ctx.method = api_ctx.method or ngx_req.get_method()
    api_ctx.uri = api_ctx.uri or ngx.var.uri

    local router = route_handler.get_router()
    local ok = router:dispatch(api_ctx.method, api_ctx.uri, api_ctx)
    if not ok then
        log.warn("not find any matched route")
        resp(403)
    end
end

function _M.header_filter()

end

function _M.log()

end

return _M
