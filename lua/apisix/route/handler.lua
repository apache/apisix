-- Copyright (C) Yuansheng Wang

local r3router = require("resty.r3")
local new_tab = require("table.new")
local route_load = require("apisix.route.load")
local core = require("apisix.core")
local ipairs = ipairs

local router
local dispatch_uri = true

local _M = {}


local function run_route(matched_params, route, api_ctx)
    api_ctx.matched_params = matched_params
    api_ctx.matched_route = route
    -- core.log.warn("run route id: ", route.id, " host: ", api_ctx.host)
end


local function _load_route(routes)
    local items = new_tab(#routes, 0)
    for i, route in ipairs(routes) do
        if type(route) == "table" then
            items[i] = {
                route.value.methods,
                route.value.uri,
                function (params, ...)
                    run_route(params, route, ...)
                end
            }
        end
    end

    core.log.info("created new r3 router")
    router = r3router.new(items)
    return router, dispatch_uri
end
_M.load_route = _load_route


do
    local routes = {}
function _M.set_routes(new_routes)
    routes = new_routes

    if router then
        router:tree_free()
        router = nil
    end

    core.log.info("update new routes")
end

function _M.get_router()
    if router == nil then
        core.log.notice("generate a empty router instance")
        return _load_route(routes)
    end

    return router, dispatch_uri
end

end -- do


function _M.init()
    route_load.init(_M.set_routes)
end


return _M
