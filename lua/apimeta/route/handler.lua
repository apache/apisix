-- Copyright (C) Yuansheng Wang

local ipairs = ipairs
local r3router = require("resty.r3")
local log = require("apimeta.core.log")
local new_tab = require("table.new")

local router
local dispatch_uri = true

local _M = {}


function _M.get_router()
    if router == nil then
        log.warn("generate a empty router instance")

        -- todo: only for test now
        return _M.load_route({
            {
                methods = {"GET"},
                uri = "/hello",
                host = "test.com",
                id = 1234,
                plugin_config = {
                    ["example-plugin"] = {i = 1, s = "s", t = {1, 2}},
                    ["new-plugin"] = {a = "a"},
                }
            },
        })
    end

    return router, dispatch_uri
end


local function run_route(matched_params, route, api_ctx)
    api_ctx.matched_params = matched_params
    api_ctx.matched_route = route

    -- log.warn("run route id: ", route.id, " host: ", api_ctx.host)
end


function _M.load_route(routes)
    if router then
        router:tree_free()
        router = nil
    end

    local items = new_tab(#routes, 0)
    for i, route in ipairs(routes) do
        items[i] = {
            route.methods,
            route.uri,
            function (params, ...)
                run_route(params, route, ...)
            end
        }
    end

    router = r3router.new(items)
    return router, dispatch_uri
end


return _M
