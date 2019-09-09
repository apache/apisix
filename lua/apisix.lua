-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local service_fetch = require("apisix.http.service").get
local admin_init = require("apisix.admin.init")
local get_var = require("resty.ngxvar").fetch
local router = require("apisix.http.router")
local ngx = ngx
local get_method = ngx.req.get_method
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR
local math = math
local error = error
local ngx_var = ngx.var
local ipairs = ipairs
local load_balancer


local _M = {version = 0.2}


function _M.http_init()
    require("resty.core")

    if require("ffi").os == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")

    -- 随机种子
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx.now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)

    core.id.init()
end

--[[
    初始化 worker
--]]
function _M.http_init_worker()
    -- 一种将事件发送到 Nginx 服务器中其他工作进程的方法。
    -- 通信是通过存储事件数据的共享内存区域进行的。
    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end

    -- 加载负载均衡处理逻辑
    load_balancer = require("apisix.http.balancer").run
    -- admin 处理逻辑初始化
    require("apisix.admin.init").init_worker()
    -- 负载均衡器逻辑初始化，从配置中心加载 pstreams 配置数据
    require("apisix.http.balancer").init_worker()
    -- router 初始化，完成指定路由引擎（ r3 或者 radixtree ）的初始化
    router.init_worker()
    -- 服务初始化，从配置中心加载 service 配置数据
    require("apisix.http.service").init_worker()
    -- 插件初始化，从本地配置文件加载 plugin 数据，初始化加载插件
    require("apisix.plugin").init_worker()
    -- 客户初始化，从配置中心加载 consumer 配置数据
    require("apisix.consumer").init_worker()
end

--[[
    在指定的阶段运行指定的插件
    @phase   阶段名称
    @plugins 插件数组
    @api_ctx apisix上下文
--]]
local function run_plugin(phase, plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugins = plugins or api_ctx.plugins
    if not plugins then
        return api_ctx
    end

    if phase == "balancer" then
        local balancer_name = api_ctx.balancer_name
        local balancer_plugin = api_ctx.balancer_plugin
        if balancer_name and balancer_plugin then
            local phase_fun = balancer_plugin[phase]
            phase_fun(balancer_plugin, api_ctx)
            return api_ctx
        end
        -- plugins 数组上的项目是一个插件存有2条数据（一条是本地加载的信息，一条是配置信息），所以循环步长为2
        for i = 1, #plugins, 2 do
            -- 取出插件对应 phase 上的功能函数
            local phase_fun = plugins[i][phase]
            -- 插件功能存在并且 balancer_name 插件名相同
            if phase_fun and
               (not balancer_name or balancer_name == plugins[i].name) then
                --调用插件的对应的phase，注意这里传的是配置的插件对象信息
                phase_fun(plugins[i + 1], api_ctx)
                if api_ctx.balancer_name == plugins[i].name then
                    api_ctx.balancer_plugin = plugins[i]
                    return api_ctx
                end
            end
        end
        return api_ctx
    end

    if phase ~= "log" then
        -- plugins 数组上的项目是一个插件存有2条数据（一条是缓存的实例对象，一条是对应的配置信息），所以循环步长为2
        for i = 1, #plugins, 2 do
            local phase_fun = plugins[i][phase]
            if phase_fun then
                -- 执行 log 动作，并且完成 response 返回
                local code, body = phase_fun(plugins[i + 1], api_ctx)
                if code or body then
                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    -- plugins 上的插件是一个插件2条（一条是缓存的实例对象，一条是对应的配置信息），所以循环步长为2
    for i = 1, #plugins, 2 do
        local phase_fun = plugins[i][phase]
        if phase_fun then
            -- 执行对应的 phase 功能
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

    local ok, err = router.router_ssl.match(api_ctx)
    if not ok then
        if err then
            core.log.error("failed to fetch ssl config: ", err)
        end
        return ngx_exit(ngx_ERROR)
    end
end


    local upstream_vars = {
        uri        = "upstream_uri",
        scheme     = "upstream_scheme",
        host       = "upstream_host",
        upgrade    = "upstream_upgrade",
        connection = "upstream_connection",
    }
    local upstream_names = {}
    for name, _ in pairs(upstream_vars) do
        core.table.insert(upstream_names, name)
    end
function _M.http_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        --从 table 资源池中提取一个命名为 api_ctx 的 lua table（如果不存在就新建）
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    -- 初始化上下文,拷贝原上下文变量到新的上下文里
    core.ctx.set_vars_meta(api_ctx)
    -- 进行路由匹配
    router.router_http.match(api_ctx)

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    -- 在路由进行匹配的时候，会把 matched_route 标记出来
    -- 详见 radixtree_uri.lua 文件 create_radixtree_router 方法
    local route = api_ctx.matched_route
    if not route then
        return core.response.exit(404)
    end

    -- 进行 grpc 匹配
    if route.value.service_protocol == "grpc" then
        return ngx.exec("@grpc_pass")
    end

    -- 确定匹配到一个 route 后，则进行后续的处理

    -- 如果 route 配置信息是映射到一个 upstream
    local upstream = route.value.upstream
    if upstream then
        for _, name in ipairs(upstream_names) do
            if upstream[name] then
                ngx_var[upstream_vars[name]] = upstream[name]
            end
        end
        -- 是否开启 websocket
        if upstream.enable_websocket then
            api_ctx.var["upstream_upgrade"] = api_ctx.var["http_upgrade"]
            api_ctx.var["upstream_connection"] = api_ctx.var["http_connection"]
        end
    end

    -- 如果 route 配置信息是映射到一个 service 的id
    if route.value.service_id then
        -- core.log.info("matched route: ", core.json.delay_encode(route.value))
        -- 根据服务的id 提取到该 service 的配置
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        local changed
        -- 插件对 service、route 进行合并
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

    -- 提取到命名为 plugins 的 lua table，初始化，空表
    local plugins = core.tablepool.fetch("plugins", 32, 0)
    -- 过滤当前匹配路由的插件,在上下文中标记出来
    api_ctx.plugins = plugin.filter(route, plugins)

    -- 执行后续操作
    run_plugin("rewrite", plugins, api_ctx)
    run_plugin("access", plugins, api_ctx)
end

--[[
    参见 http_access_phase 方法，基本上是一致的。
--]]
function _M.grpc_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    router.router_http.match(api_ctx)

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

function _M.http_body_filter_phase()
    run_plugin("body_filter")
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

--[[
    执行balancer 阶段
--]]
function _M.http_balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return core.response.exit(500)
    end

    -- first time
    if not api_ctx.balancer_name then
        -- 执行插件的 balancer 阶段，捆绑上自己实现的 balancer
        run_plugin("balancer", nil, api_ctx)
        if api_ctx.balancer_name then
            return
        end
    -- 实现了一个自己的负载插件，没有走默认的 balancer
    if api_ctx.balancer_name and api_ctx.balancer_name ~= "default" then
        return run_plugin("balancer", nil, api_ctx)
    end

    -- 走默认的 balancer 处理
    api_ctx.balancer_name = "default"
    load_balancer(api_ctx.matched_route, api_ctx)
end


do
    local router

function _M.http_admin()
    if not router then
        router = admin_init.get()
    end

    -- core.log.info("uri: ", get_var("uri"), " method: ", get_method())
    local ok = router:dispatch(get_var("uri"), {method = get_method()})
    if not ok then
        ngx_exit(404)
    end
end

end -- do


return _M
