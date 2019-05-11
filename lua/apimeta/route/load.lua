-- Copyright (C) Yuansheng Wang

local log = require("apimeta.core.log")
local config = require("apimeta.core.config")
local table_nkeys = require("table.nkeys")
local new_tab = require("table.new")
local insert_tab = table.insert
local ngx = ngx
local pcall = pcall
local pairs = pairs
local callback


local _M = {version = 0.1}


local function load()
    local routes, err = config.routes()
    if not routes then
        log.error("failed to fetch routes: ", err)
        return
    end

    local arr_routes = new_tab(table_nkeys(routes), 0)
    for route_id, route in pairs(routes) do
        route.id = route_id
        insert_tab(arr_routes, route)
    end

    -- log.warn(apimeta.json.encode(arr_routes))
    if callback then
        callback(arr_routes)
    end
end


do
    local running

function _M.load(premature)
    if premature or running then
        return
    end

    running = true
    local ok, err = pcall(load)
    running = false

    if not ok then
        log.error("failed to call `load` function: ", err)
    end
end

end -- do


function _M.init(callback_fun)
    callback = callback_fun
end


function _M.init_worker()
    ngx.timer.every(1, _M.load)
end


return _M
