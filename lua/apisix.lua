-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local router = require("apisix.route").get
local plugin = require("apisix.plugin")
local load_balancer = require("apisix.balancer").run
local service_fetch = require("apisix.service").get
local ngx = ngx


local _M = {version = 0.1}


function _M.init()
    require("resty.core")

    if require("ffi").os == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")

    --
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx.now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)

    core.id.init()
end


function _M.init_worker()
    require("apisix.route").init_worker()
    require("apisix.balancer").init_worker()
    require("apisix.service").init_worker()
    require("apisix.consumer").init_worker()
    require("apisix.heartbeat").init_worker()
end


local function run_plugin(phase, filter_plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    filter_plugins = filter_plugins or api_ctx.filter_plugins
    if not filter_plugins then
        return api_ctx
    end

    if phase ~= "log" then
        for i = 1, #filter_plugins, 2 do
            local phase_fun = filter_plugins[i][phase]
            if phase_fun then
                local code, body = phase_fun(filter_plugins[i + 1], api_ctx)
                if code or body then
                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    for i = 1, #filter_plugins, 2 do
        local phase_fun = filter_plugins[i][phase]
        if phase_fun then
            phase_fun(filter_plugins[i + 1], api_ctx)
        end
    end

    return api_ctx
end


function _M.access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    end

    core.ctx.set_vars_meta(api_ctx)
    ngx_ctx.api_ctx = api_ctx

    local method = api_ctx.var.method
    local uri =  api_ctx.var.uri
    api_ctx.uri_parse_param = core.tablepool.fetch("uri_parse_param", 0, 4)
    -- local host = api_ctx.var.host -- todo: support host
    local ok = router():dispatch2(api_ctx.uri_parse_param, method, uri, api_ctx)
    if not ok then
        core.log.info("not find any matched route")
        return core.response.exit(404)
    end

    -- core.log.warn("route: ",
    --               core.json.encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if not route then
        return
    end

    if route.value.service_id then
        -- core.log.warn("matched route: ", core.json.encode(route.value))
        local service = service_fetch(route.value.service_id)
        local changed
        route, changed = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route

        if changed then
            api_ctx.conf_type = "route&service"
            api_ctx.conf_version = route.modifiedIndex .. "&"
                                   .. service.modifiedIndex
            api_ctx.conf_id = route.value.id .. "&"
                              .. service.value.id
        else
            api_ctx.conf_type = "service"
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
    run_plugin("access", api_ctx.filter_plugins, api_ctx)
end

function _M.header_filter_phase()
    run_plugin("header_filter")
end

function _M.log_phase()
    local api_ctx = run_plugin("log")
    if api_ctx then
        core.tablepool.release("uri_parse_param", api_ctx.uri_parse_param)
        core.ctx.release_vars(api_ctx)
        core.tablepool.release("api_ctx", api_ctx)
    end
end

function _M.balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx or not api_ctx.filter_plugins then
        return
    end

    load_balancer(api_ctx.matched_route, api_ctx)
end

return _M
