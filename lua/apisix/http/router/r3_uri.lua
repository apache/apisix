-- Copyright (C) Yuansheng Wang

local require = require
local r3router = require("resty.r3")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local local_conf = core.config.local_conf
local ipairs = ipairs
local type = type
local error = error
local str_reverse = string.reverse
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

    local conf = local_conf()
    local route_idx = conf and conf.apisix and conf.apisix.route_idx

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            idx = idx + 1
            if route_idx == "host+uri" then
                local host = route.value.host
                if not host then
                    host = [=[{domain:[^/]+}]=]

                else
                    host = str_reverse(host)
                    if host:sub(#host) == "*" then
                        host = host:sub(1, #host - 1) .. "{prefix:.*}"
                    end
                end

                core.log.info("route rule: ", host .. route.value.uri)
                route_items[idx] = {
                    path = host .. route.value.uri,
                    method = route.value.methods,
                    handler = function (params, api_ctx)
                        api_ctx.matched_params = params
                        api_ctx.matched_route = route
                    end
                }

            else
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
    end

    core.log.info("route items: ", core.json.delay_encode(route_items, true))
    local r3 = r3router.new(route_items)
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
    match_opts.host = api_ctx.var.host

    local ok = router:dispatch2(nil, api_ctx.var.uri, match_opts, api_ctx)
    if not ok then
        core.log.info("not find any matched route")
        return core.response.exit(404)
    end

    return true
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
