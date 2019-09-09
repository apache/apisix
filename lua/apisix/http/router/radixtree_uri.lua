-- Copyright (C) Yuansheng Wang

local require = require
local router = require("resty.radixtree")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local user_routes
local cached_version


local _M = {version = 0.1}


    local uri_routes = {}
    -- 用来存放初始化的radixtree路由
    local uri_router
local function create_radixtree_router(routes)
    routes = routes or {}

    local api_routes = plugin.api_routes()
    core.table.clear(uri_routes)

    --针对插件里需要进行url拦截的，创建指定的路由动作，路由动作是插件里定义的
    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            core.table.insert(uri_routes, {
                path = route.uri,
                handler = route.handler,
                method = route.methods,
            })
        end
    end

    --对传过来的routes 进行路由创建，路由动作，标记当前的路由的参数、匹配的理由route
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            core.table.insert(uri_routes, {
                path = route.value.uri,
                method = route.value.methods,
                host = route.value.host,
                remote_addr = route.value.remote_addr,
                vars = route.value.vars,
                handler = function (api_ctx)
                    api_ctx.matched_params = nil
                    api_ctx.matched_route = route
                end
            })
        end
    end

    core.log.info("route items: ", core.json.delay_encode(uri_routes, true))
    uri_router = router.new(uri_routes)
end


    local match_opts = {}
function _M.match(api_ctx)
    -- 如果配置版本不匹配，则缓存数据已经落后，需要重新创建radixtree路由
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_radixtree_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    -- 如果数据不存在
    if not uri_router then
        core.log.error("failed to fetch valid `uri` router: ")
        return core.response.exit(404)
    end

    -- 构建匹配选项
    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method
    match_opts.host = api_ctx.var.host
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var

    -- 路由匹配分发
    local ok = uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if not ok then
        core.log.info("not find any matched route")
        return core.response.exit(404)
    end

    return true
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.init_worker()
    local err
    user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route
        })
    if not user_routes then
        error("failed to create etcd  for finstanceetching /routes : " .. err)
    end
end


return _M
