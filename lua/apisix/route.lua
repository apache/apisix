-- Copyright (C) Yuansheng Wang

local r3router = require("resty.r3")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local conf_routes


local _M = {}

    local empty_tab = {}
local function create_r3_router(routes)
    routes = routes or empty_tab

    local api_routes = plugin.api_routes()
    local items = core.table.new(#api_routes + #routes, 0)
    local idx = 0

    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            idx = idx + 1
            items[idx] = route
        end
    end

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            idx = idx + 1
            items[idx] = {
                route.value.methods,
                route.value.uri,
                function (params, api_ctx)
                    api_ctx.matched_params = params
                    api_ctx.matched_route = route
                end
            }
        end
    end

    return r3router.new(items)
end


function _M.get()
    -- core.log.warn("conf_routes.conf_version: ", conf_routes.conf_version)
    return core.lrucache.global("/routes", conf_routes.conf_version,
                                create_r3_router, conf_routes.values)
end


function _M.init_worker()
    local err
    conf_routes, err = core.config.new("/routes",
                            {
                                automatic = true,
                                item_schema = core.schema.route
                            })
    if not conf_routes then
        error("failed to create etcd instance to fetch /routes "
              .. "automaticly: " .. err)
    end
end


return _M
