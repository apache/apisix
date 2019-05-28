-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local router = require("apisix.route").get
local plugin = require("apisix.plugin")
local new_tab = require("table.new")
local load_balancer = require("apisix.balancer") .run
local service_fetch = require("apisix.service").get
local ngx = ngx


local _M = {version = 0.1}


function _M.init()
    require("resty.core")
    require("ngx.re").opt("jit_stack_size", 200 * 1024)
    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")
end


function _M.init_worker()
    require("apisix.route").init_worker()
    require("apisix.balancer").init_worker()
    require("apisix.plugin").init_worker()
    require("apisix.service").init_worker()
end


local function run_plugin(phase, filter_plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    filter_plugins = filter_plugins or api_ctx.filter_plugins
    if not filter_plugins then
        return
    end

    for i = 1, #filter_plugins, 2 do
        local phase_fun = filter_plugins[i][phase]
        if phase_fun then
            local code, body = phase_fun(filter_plugins[i + 1], api_ctx)
            if phase ~= "log" and type(code) == "number" or body then
                core.response.exit(code, body)
            end
        end
    end
end


function _M.rewrite_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        -- todo: reuse this table
        api_ctx = new_tab(0, 32)
    end

    core.ctx.set_vars_meta(api_ctx)
    local method = api_ctx.var["method"]
    local uri =  api_ctx.var["uri"]
    -- local host = api_ctx.var["host"] -- todo: support host

    -- run the api router
    local api_router = plugin.api_router()
    if api_router and api_router.dispatch then
        local ok = api_router:dispatch(method, uri, api_ctx)
        if ok then
            -- core.log.warn("finish api route")
            return
        end
    end

    ngx_ctx.api_ctx = api_ctx

    local ok = router():dispatch(method, uri, api_ctx)
    if not ok then
        core.log.warn("not find any matched route")
        return core.response.exit(404)
    end

    -- core.log.warn("route: ",
    --               core.json.encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if route.value.service_id then
        -- core.log.warn("matched route: ", core.json.encode(route.value))
        local service = service_fetch(route.value.service_id)
        local changed
        route, changed = plugin.merge_service_route(service, route)

        if changed then
            api_ctx.conf_type = "route&service"
            api_ctx.conf_version = route.modifiedIndex .. "&"
                                   .. service.modifiedIndex
            api_ctx.conf_id = route.value.id .. "&"
                              .. service.value.id
        else
            api_ctx.conf_type = "route"
            api_ctx.conf_version = route.modifiedIndex
            api_ctx.conf_id = route.value.id
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end

    api_ctx.filter_plugins = plugin.filter(route)

    run_plugin("rewrite", api_ctx.filter_plugins, api_ctx)
end

function _M.access_phase()
    run_plugin("access")
end

function _M.header_filter_phase()
    run_plugin("header_filter")
end

function _M.log_phase()
    run_plugin("log")
end

function _M.balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx or not api_ctx.filter_plugins then
        return
    end

    -- TODO: fetch the upstream by upstream_id
    load_balancer(api_ctx.matched_route, api_ctx)
end

return _M
