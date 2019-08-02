-- Copyright (C) Yuansheng Wang

local log = require("apisix.core.log")
local yaml = require("apisix.core.yaml")
local ngx = ngx
local io_open = io.open
local type = type
local local_conf_path = ngx.config.prefix() .. "conf/config.yaml"
local config_data


local _M = {
    version = 0.2,
}


local function read_file(path)
    local file, err = io_open(path, "rb")   -- read as binary mode
    if not file then
        log.error("faild to read config file:" .. path, ", error info:", err)
        return nil, err
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end

function _M.clear_cache()
    config_data = nil
end


function _M.local_conf(force)
    if not force and config_data then
        return config_data
    end

    local yaml_config, err = read_file(local_conf_path)
    if type(yaml_config) ~= "string" then
        return nil, "failed to read config file:" .. err
    end

    config_data = yaml.parse(yaml_config)
    return config_data
end


return _M
