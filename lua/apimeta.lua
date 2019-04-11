-- Copyright (C) Yuansheng Wang

local require = require
local log = require("apimeta.comm.log")
local resp = require("apimeta.comm.resp")
local route_handler = require("apimeta.route.handler")
local new_tab = require("table.new")
local ngx = ngx
local ngx_req = ngx.req
local ngx_var = ngx.var

local _M = {}

function _M.init()
    require("resty.core")
    require("ngx.re").opt("jit_stack_size", 200 * 1024)
    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")
end

function _M.init_worker()
    require("apimeta.route.load").init_worker()
end

function _M.access()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        -- todo: reuse this table
        api_ctx = new_tab(0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    api_ctx.method = api_ctx.method or ngx_req.get_method()
    api_ctx.uri = api_ctx.uri or ngx_var.uri
    api_ctx.host = api_ctx.host or ngx_var.host

    local router, dispatch_uri = route_handler.get_router()
    local ok
    if dispatch_uri then
        ok = router:dispatch(api_ctx.method, api_ctx.uri, api_ctx)
    else
        ok = router:dispatch(api_ctx.method, api_ctx.host .. api_ctx.uri,
                             api_ctx)
    end
    if not ok then
        log.warn("not find any matched route")
        resp(404)
    end
end

function _M.header_filter()

end

function _M.log()

end

return _M
