-- Copyright (C) Yuansheng Wang

local log = require("apimeta.core.log")
local etcd = require("resty.etcd")
local new_tab = require("table.new")
local insert_tab = table.insert
local etcd_cli


local _M = {version = 0.1}


local function readdir(key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:readdir(key, true)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body or {}

    if body.message then
        return nil, body.message
    end

    return body.node
end

do
    local routes = nil
    local routes_hash = nil
    local prev_index = nil

function _M.routes()
    if routes == nil then
        local node, err = readdir("/user_routes")
        if not node then
            return nil, err
        end

        if not node.dir then
            return nil, "/user_routes is not a dir"
        end

        routes = new_tab(#node.nodes, 0)
        routes_hash = new_tab(0, #node.nodes)

        for _, item in ipairs(node.nodes) do
            routes_hash[item.key] = item.value
            insert_tab(routes, item.value)

            if not prev_index or item.modifiedIndex > prev_index then
                prev_index = item.modifiedIndex
            end
        end

        ngx.log(ngx.WARN, "fetch all routes")
    end

    return routes
end

end -- do


function _M.init(opts)
    if etcd_cli then
        return true
    end

    local err
    etcd_cli, err = etcd.new(opts)
    return etcd_cli and true, err
end


return _M
