-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local route_handler = require("apisix.route.handler")
local base_plugin = require("apisix.base_plugin")
local new_tab = require("table.new")
local load_balancer = require("apisix.balancer") .run
local ngx = ngx
local ngx_req = ngx.req
local ngx_var = ngx.var


local _M = {version = 0.1}


function _M.init()
    require("resty.core")
    require("ngx.re").opt("jit_stack_size", 200 * 1024)
    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")

    require("apisix.route.handler").init()
end


function _M.init_worker()
    require("apisix.route.load").init_worker()
    require("apisix.balancer").init_worker()
end


function _M.rewrite_phase()
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
        core.log.info("not find any matched route")
        return core.resp(404)
    end

    -- todo: move those code to another single file
    -- todo optimize: cache `local_supported_plugins`
    local local_supported_plugins, err = base_plugin.load()
    if not local_supported_plugins then
        ngx.say("failed to load plugins: ", err)
    end

    local filter_plugins = base_plugin.filter_plugin(
        api_ctx.matched_route, local_supported_plugins)

    api_ctx.filter_plugins = filter_plugins
    api_ctx.conf_version = api_ctx.matched_route.modifiedIndex
    -- todo: fetch the upstream node status, it may be stored in
    -- different places.

    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.rewrite then
            plugin.rewrite(filter_plugins[i + 1],
                           api_ctx.conf_version)
        end
    end
end

function _M.access_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.access then
            plugin.access(filter_plugins[i + 1],
                          api_ctx.conf_version)
        end
    end
end

function _M.header_filter_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.header_filter then
            plugin.header_filter(filter_plugins[i + 1],
                                 api_ctx.conf_version)
        end
    end
end

function _M.log_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.log then
            plugin.log(filter_plugins[i + 1],
                       api_ctx.conf_version)
        end
    end
end

function _M.balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    -- TODO: fetch the upstream by upstream_id
    load_balancer(api_ctx.matched_route, api_ctx.conf_version)
end

return _M
