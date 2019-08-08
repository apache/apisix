-- Copyright (C) Yuansheng Wang

local require = require
local r3router = require("resty.r3")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local str_reverse = string.reverse
local user_routes
local cached_version


local _M = {version = 0.2}

    local only_uri_routes = {}
    local only_uri_router
local function create_only_uri_router()
    local routes = plugin.api_routes()

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            core.table.insert(only_uri_routes, {
                path = route.uri,
                handler = route.handler,
                method = route.methods,
            })
        end
    end

    only_uri_router = r3router.new(only_uri_routes)
    only_uri_router:compile()
    return true
end


    local host_uri_routes = {}
    local host_uri_router
local function push_valid_route(route)
    if type(route) ~= "table" then
        return
    end

    local host = route.value.host
    if not host then
        core.table.insert(only_uri_routes, {
            path = route.value.uri,
            method = route.value.methods,
            handler = function (params, api_ctx)
                api_ctx.matched_params = params
                api_ctx.matched_route = route
            end
        })
        return
    end

    host = str_reverse(host)
    if host:sub(#host) == "*" then
        host = host:sub(1, #host - 1) .. "{host_prefix}"
    end

    core.log.info("route rule: ", host .. route.value.uri)
    core.table.insert(host_uri_routes, {
        path = "/" .. host .. route.value.uri,
        method = route.value.methods,
        handler = function (params, api_ctx)
            api_ctx.matched_params = params
            api_ctx.matched_route = route
        end
    })

    return
end

local function create_r3_router(routes)
    core.table.clear(only_uri_routes)
    core.table.clear(host_uri_routes)

    for _, route in ipairs(routes or {}) do
        push_valid_route(route)
    end

    create_only_uri_router()

    core.log.info("route items: ",
                  core.json.delay_encode(host_uri_routes, true))
    host_uri_router = r3router.new(host_uri_routes)
    host_uri_router:compile()
end


    local match_opts = {}
function _M.match(api_ctx)
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_r3_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    if not host_uri_router then
        core.log.error("failed to fetch valid `host+uri` router: ")
        return core.response.exit(404)
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method

    local host_uri = "/" .. str_reverse(api_ctx.var.host) .. api_ctx.var.uri
    local ok = host_uri_router:dispatch2(nil, host_uri, match_opts, api_ctx)
    if ok then
        return true
    end

    ok = only_uri_router:dispatch2(nil, api_ctx.var.uri, match_opts, api_ctx)
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


function _M.init_worker()
    local err
    user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
