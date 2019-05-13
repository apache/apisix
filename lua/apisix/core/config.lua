-- Copyright (C) Yuansheng Wang
local log = require("apisix.core.log")
local yaml = require("apisix.core.yaml")
local setmetatable = setmetatable
local require = require
local ngx = ngx
local io_open = io.open
local type = type
local local_conf_path = ngx.config.prefix() .. "conf/config.yaml"


local _M = {version = 0.1}



local function read_file(path)
    local file = io_open(path, "rb")   -- read and binary mode
    if not file then
        return nil
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end


local function get_local_conf()
    local yaml_config = read_file(local_conf_path)
    if type(yaml_config) ~= "string" then
        return nil, "failed to read config file"
    end

    return yaml.parse(yaml_config)
end
_M.local_conf = get_local_conf


function _M.init()
    local local_conf, err = get_local_conf()
    if not local_conf then
        log.error("failed to read local config file: ", err)
        return
    end

    local config = require("apisix.core.config_etcd")
    local ok
    ok, err = config.init(local_conf.etcd)
    if not ok then
        log.error("failed to init etcd component: ", err)
        return
    end

    setmetatable(_M, {__index = config})
end


return _M
