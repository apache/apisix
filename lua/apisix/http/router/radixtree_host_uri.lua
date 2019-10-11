-- Copyright (C) bobo pan

local require = require
local router = require("resty.radixtree")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local str_reverse = string.reverse
local error = error
local user_routes
local cached_version
local only_uri_routes = {}
local only_uri_router
local host_uri_routes = {}
local host_uri_router


local _M = {version = 0.1}


local function create_only_uri_router()
    local routes = plugin.api_routes()
    core.log.error("routes", core.json.encode(routes))
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            core.table.insert(only_uri_routes, {
                paths = route.uris or route.uri,
                handler = route.handler,
                method = route.methods,
            })
        end
    end
    only_uri_router = router.new(only_uri_routes)
    return true
end


local function add_host_uri_routes(paths, hosts, route)
    core.log.info("route rule: ", paths)
    core.table.insert(host_uri_routes, {
        paths = paths,
        methods = route.value.methods,
        hosts = hosts,
        remote_addrs = route.value.remote_addrs or route.value.remote_addr,
        vars = route.value.vars,
        handler = function (api_ctx)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
        end
    })
end


local function push_radixtree_host_router(route)
    if type(route) ~= "table" then
        return
    end

    local host = route.value.host
    local hosts = route.value.hosts
    local uri = route.value.uris or route.value.uri
    if (not host or type(host) ~= "string") and (not hosts or type(hosts) ~= "table") then
        core.table.insert(only_uri_routes, {
            paths = route.value.uris or route.value.uri,
            method = route.value.methods,
            hosts = hosts or host,
            remote_addrs = route.value.remote_addrs or route.value.remote_addr,
            vars = route.value.vars,
            handler = function (api_ctx)
                api_ctx.matched_params = nil
                api_ctx.matched_route = route
            end
        })
        return
    end
    --more hosts
    if hosts and type(hosts) == "table" then
        for _, host_path in ipairs(hosts) do
            local paths = "/" .. str_reverse(host_path)
            if type(uri) == 'table' then
                for _, uri_path in ipairs(uri) do
                    add_host_uri_routes(paths .. uri_path, host_path, route)
                end
            else
                add_host_uri_routes(paths .. uri, host_path, route)
            end
        end
    end

    -- only one host
    if host and type(host) == "string" then
        local paths = "/" .. str_reverse(host)
        if type(uri) == 'table' then
            for _, uri_path in ipairs(uri) do
                add_host_uri_routes(paths .. uri_path, host, route)
            end
        else
            add_host_uri_routes(paths .. uri, host, route)
        end
    end
    return
end


local function create_radixtree_router(routes)
    core.table.clear(host_uri_routes)
    core.table.clear(only_uri_routes)
    for _, route in ipairs(routes or {}) do
        push_radixtree_host_router(route)
    end

    create_only_uri_router()

    core.log.info("route items: ",
                  core.json.delay_encode(host_uri_routes, true))
    host_uri_router = router.new(host_uri_routes)
end


    local match_opts = {}
function _M.match(api_ctx)
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_radixtree_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    if not host_uri_router then
        core.log.error("failed to fetch valid `uri` router: ")
        return core.response.exit(404)
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method
    match_opts.host = api_ctx.var.host
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var

    local host_uri = "/" .. str_reverse(api_ctx.var.host) .. api_ctx.var.uri
    local ok = host_uri_router:dispatch(host_uri, match_opts, api_ctx)
    if ok then
        return true
    end

    ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if ok then
        return true
    end

    core.log.info("not find any matched route")
    return core.response.exit(404)
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.init_worker(filter)
    local err
    user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route,
            filter = filter,
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
