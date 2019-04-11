-- Copyright (C) Yuansheng Wang

local ngx = ngx
local ipairs = ipairs
local r3router = require("resty.r3")
local log = require("apimeta.comm.log")
local insert_tab = table.insert
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
            },
        })
    end

    return router, dispatch_uri
end


local function run_route(params, route, api_ctx)
    ngx.say("run route id: ", route.id, " host: ", api_ctx.host)
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
                return run_route(params, route, ...)
            end
        }
    end

    router = r3router.new(items)
    return router, dispatch_uri
end


return _M
