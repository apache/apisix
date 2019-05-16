-- Copyright (C) Yuansheng Wang

local log = require("apisix.core.log")
local etcd = require("apisix.core.config_etcd")
local table_nkeys = require("table.nkeys")
local new_tab = require("table.new")
local insert_tab = table.insert
local ngx = ngx
local pcall = pcall
local pairs = pairs
local callback


local _M = {version = 0.1}


local function load(etcd_routes)
    local routes, err = etcd_routes:fetch()
    if not routes then
        if err ~= "timeout" then
            log.error("failed to fetch routes: ", err)
        end
        return
    end

    local arr_routes = new_tab(table_nkeys(routes), 0)
    for route_id, route in pairs(routes) do
        if type(route) == "table" then
            route.id = route_id
            insert_tab(arr_routes, route)
        end
    end

    -- log.warn(apisix.json.encode(arr_routes))
    if callback then
        callback(arr_routes)
    end
end


do
    local running
    local etcd_routes

function _M.load(premature)
    if premature or running then
        return
    end

    if not etcd_routes then
        etcd_routes = etcd.new("/user_routes")
    end

    running = true
    local ok, err = pcall(load, etcd_routes)
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
