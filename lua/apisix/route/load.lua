-- Copyright (C) Yuansheng Wang

local core = require("apisix.core")
local etcd = require("apisix.core.config_etcd")
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
            core.log.error("failed to fetch routes: ", err)
        end
        return
    end

    local arr_routes = core.table.new(core.table.nkeys(routes), 0)
    for route_id, route in pairs(routes) do
        if type(route) == "table" then
            route.id = route_id
            insert_tab(arr_routes, route)
        end
    end

    -- core.log.warn(apisix.json.encode(arr_routes))
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
        core.log.error("failed to call `load` function: ", err)
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
