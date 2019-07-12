-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local router = require("apisix.http.route").get
local plugin = require("apisix.plugin")
local load_balancer = require("apisix.http.balancer").run
local service_fetch = require("apisix.http.service").get
local ssl_match = require("apisix.http.ssl").match
local admin_init = require("apisix.admin.init")
local get_var = require("resty.ngxvar").fetch
local ngx = ngx
local get_method = ngx.req.get_method
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR
local math = math
local match_opts = {}


local _M = {version = 0.1}


function _M.http_init()
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


function _M.http_init_worker()
    require("apisix.admin.init").init_worker()

    require("apisix.http.route").init_worker()
    require("apisix.http.service").init_worker()
    require("apisix.http.ssl").init_worker()

    require("apisix.plugin").init_worker()
    require("apisix.consumer").init_worker()
end


local function run_plugin(phase, plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugins = plugins or api_ctx.plugins
    if not plugins then
        return api_ctx
    end

    if phase ~= "log" then
        for i = 1, #plugins, 2 do
            local phase_fun = plugins[i][phase]
            if phase_fun then
                local code, body = phase_fun(plugins[i + 1], api_ctx)
                if code or body then
                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    for i = 1, #plugins, 2 do
        local phase_fun = plugins[i][phase]
        if phase_fun then
            phase_fun(plugins[i + 1], api_ctx)
        end
    end

    return api_ctx
end


function _M.http_ssl_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    local ok, err = ssl_match(api_ctx)
    if not ok then
        if err then
            core.log.error("failed to fetch ssl config: ", err)
        end
        return ngx_exit(ngx_ERROR)
    end
end


function _M.http_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)
    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method
    match_opts.host = api_ctx.var.host

    local ok = router():dispatch2(nil, api_ctx.var.uri, match_opts, api_ctx)
    if not ok then
        core.log.info("not find any matched route")
        return core.response.exit(404)
    end

    core.log.info("route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if not route then
        return core.response.exit(404)
    end

    if route.value.service_id then
        -- core.log.info("matched route: ", core.json.delay_encode(route.value))
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

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
            api_ctx.conf_version = service.modifiedIndex
            api_ctx.conf_id = service.value.id
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.filter(route, plugins)

    run_plugin("rewrite", plugins, api_ctx)
    run_plugin("access", plugins, api_ctx)
end


function _M.http_header_filter_phase()
    run_plugin("header_filter")
end


function _M.http_log_phase()
    local api_ctx = run_plugin("log")
    if api_ctx then
        if api_ctx.uri_parse_param then
            core.tablepool.release("uri_parse_param", api_ctx.uri_parse_param)
        end

        core.ctx.release_vars(api_ctx)
        if api_ctx.plugins then
            core.tablepool.release("plugins", api_ctx.plugins)
        end

        core.tablepool.release("api_ctx", api_ctx)
    end
end


function _M.http_balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return core.response.exit(500)
    end

    load_balancer(api_ctx.matched_route, api_ctx)
end


do
    local router

function _M.http_admin()
    if not router then
        router = admin_init.get()
    end

    -- core.log.info("uri: ", get_var("uri"), " method: ", get_method())
    local ok = router:dispatch(get_var("uri"), get_method())
    if not ok then
        ngx_exit(404)
    end
end

end -- do


return _M
