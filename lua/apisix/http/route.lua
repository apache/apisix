-- Copyright (C) Yuansheng Wang

local r3router = require("resty.r3")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local routes


local _M = {version = 0.1}


    local empty_tab = {}
    local route_items
local function create_r3_router(routes)
    routes = routes or empty_tab

    local api_routes = plugin.api_routes()
    route_items = core.table.new(#api_routes + #routes, 0)
    local idx = 0

    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            idx = idx + 1
            route_items[idx] = {
                path = route.uri,
                handler = route.handler,
                method = route.methods,
            }
        end
    end

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            idx = idx + 1
            route_items[idx] = {
                path = route.value.uri,
                method = route.value.methods,
                host = route.value.host,
                handler = function (params, api_ctx)
                    api_ctx.matched_params = params
                    api_ctx.matched_route = route
                end
            }
        end
    end

    core.log.info("route items: ", core.json.delay_encode(route_items, true))
    local r3 = r3router.new(route_items)
    r3:compile()
    return r3
end


function _M.get()
    core.log.info("routes conf_version: ", routes.conf_version)
    return core.lrucache.global("/routes", routes.conf_version,
                                create_r3_router, routes.values)
end


function _M.routes()
    if not routes then
        return nil, nil
    end

    return routes.values, routes.conf_version
end


function _M.init_worker()
    local err
    routes, err = core.config.new("/routes",
                            {
                                automatic = true,
                                item_schema = core.schema.route
                            })
    if not routes then
        error("failed to create etcd instance for fetching routes : " .. err)
    end


    require("apisix.http.balancer").init_worker()
end


return _M
