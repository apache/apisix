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
    local uri_router
local function create_radixtree_router(routes)
    routes = routes or {}

    local api_routes = plugin.api_routes()
    core.table.clear(uri_routes)

    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            core.table.insert(uri_routes, {
                path = route.uri,
                handler = route.handler,
                method = route.methods,
            })
        end
    end

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            core.table.insert(uri_routes, {
                path = route.value.uri,
                method = route.value.methods,
                host = route.value.host,
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
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_radixtree_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    if not uri_router then
        core.log.error("failed to fetch valid `uri` router: ")
        return core.response.exit(404)
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.method
    match_opts.host = api_ctx.var.host

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
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
