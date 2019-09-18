local fetch_local_conf = require("apisix.core.config_local").local_conf
local etcd = require("resty.etcd")
local clone_tab = require("table.clone")

local _M = {version = 0.1}


local function new()
    local local_conf, err = fetch_local_conf()
    if not local_conf then
        return nil, nil, err
    end

    local etcd_conf = clone_tab(local_conf.etcd)
    local prefix = etcd_conf.prefix
    etcd_conf.prefix = nil

    local etcd_cli
    etcd_cli, err = etcd.new(etcd_conf)
    if not etcd_cli then
        return nil, nil, err
    end

    return etcd_cli, prefix
end
_M.new = new


function _M.get(key)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:get(prefix .. key)
end


function _M.set(key, value)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:set(prefix .. key, value)
end


function _M.push(key, value)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:push(prefix .. key, value)
end


function _M.delete(key)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:delete(prefix .. key)
end


function _M.server_version(key)
    local etcd_cli, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:version()
end


return _M
