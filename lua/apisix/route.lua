-- Copyright (C) Yuansheng Wang

local r3router = require("resty.r3")
local core = require("apisix.core")
local ipairs = ipairs
local type = type
local error = error
local conf_routes


local _M = {}


local function create_r3_router(routes)
    local items = core.table.new(#routes, 0)
    for i, route in ipairs(routes) do
        if type(route) == "table" then
            items[i] = {
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
    -- core.log.warn("conf_routes.version: ", conf_routes.version)
    return core.lrucache.global("/routes", conf_routes.version,
                                create_r3_router, conf_routes.values)
end


function _M.init_worker()
    local err
    conf_routes, err = core.config.new("/routes", {automatic = true})
    if not conf_routes then
        error("failed to create etcd instance to fetch /routes "
              .. "automaticly: " .. err)
    end
end


return _M
