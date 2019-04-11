-- Copyright (C) Yuansheng Wang

local r3router = require("resty.r3")
local log = require("apimeta.comm.log")
local insert_tab = table.insert
local new_tab = require("table.new")

local router

local _M = {}


function _M.get_router()
    if router == nil then
        log.warn("generate a empty router instance")
        return _M.load({ {methods = {"GET"}, uri = "/hello", router_id = "xx"} })
    end

    return router
end


local function run_route(params, route, ...)
    ngx.say("run route")
end


function _M.load(routes)
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
                return run_route(params, router, ...)
            end
        }
    end

    router = r3router.new(items)
    return router
end


return _M
