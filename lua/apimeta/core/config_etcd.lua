-- Copyright (C) Yuansheng Wang

local etcd = require("resty.etcd")
local etcd_cli

local _M = {version = 0.1}


local function get(key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:get(key)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body or {}
    -- log.warn("etcd value: ", apimeta.json.encode(body))

    if body.message then
        return nil, body.message
    end

    return body.node and body.node.value
end


function _M.routes()
    local routes, err = get("/user_routes")
    return routes, err
end


function _M.init(opts)
    local err
    etcd_cli, err = etcd.new(opts)
    return etcd_cli and true, err
end


return _M
