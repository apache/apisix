-- Copyright (C) Yuansheng Wang

local require = require
local r3router = require("resty.r3")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local str_reverse = string.reverse
local routes


local _M = {version = 0.1}

    local api_routes = {}
    local api_router
local function create_api_router()
    local api_routes = plugin.api_routes()
    core.table.clear(api_routes)

    local idx = 0
    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            idx = idx + 1
            api_routes[idx] = {
                path = route.uri,
                handler = route.handler,
                method = route.methods,
            }
        end
    end

    api_router = r3router.new(api_routes)
    api_router:compile()
    return true
end


    local req_routes = {}
    local req_routes_idx = 0
local function push_valid_route(route)
    if type(route) ~= "table" then
        return
    end

    local host = route.value.host
    if not host then
        core.log.error("missing `host` field in route: ",
                        core.json.delay_encode(route))
        return
    end

    host = str_reverse(host)
    if host:sub(#host) == "*" then
        host = host:sub(1, #host - 1) .. "{host_prefix}"
    end

    core.log.info("route rule: ", host .. route.value.uri)
    req_routes_idx = req_routes_idx + 1
    req_routes[req_routes_idx] = {
        path = "/" .. host .. route.value.uri,
        method = route.value.methods,
        handler = function (params, api_ctx)
            api_ctx.matched_params = params
            api_ctx.matched_route = route
        end
    }

    return
end

local function create_r3_router(routes)
    create_api_router()

    core.table.clear(req_routes)
    req_routes_idx = 0

    for _, route in ipairs(routes or {}) do
        push_valid_route(route)
    end

    core.log.info("route items: ", core.json.delay_encode(req_routes, true))
    local r3 = r3router.new(req_routes)
    r3:compile()
    return r3
end


    local match_opts = {}
function _M.match(api_ctx)
    local router, err = core.lrucache.global("/routes", routes.conf_version,
                                             create_r3_router, routes.values)
    if not router then
        core.log.error("failed to fetch http router: ", err)
        return core.response.exit(404)
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method

    local host_uri = "/" .. str_reverse(api_ctx.var.host) .. api_ctx.var.uri
    local ok = router:dispatch2(nil, host_uri, match_opts, api_ctx)
    if ok then
        return true
    end

    ok = router:dispatch2(nil, api_ctx.var.uri, match_opts, api_ctx)
    if ok then
        return true
    end

    core.log.info("not find any matched route")
    return core.response.exit(404)
end


function _M.routes()
    if not routes then
        return nil, nil
    end

    return routes.values, routes.conf_version
end


function _M.init_worker()
    local err
    routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route
        })
    if not routes then
        error("failed to create etcd instance for fetching routes : " .. err)
    end
end


return _M
