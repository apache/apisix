-- Copyright (C) Yuansheng Wang

local log = require("apisix.core.log")
local yaml = require("apisix.core.yaml")
local ngx = ngx
local io_open = io.open
local type = type
local local_conf_path = ngx.config.prefix() .. "conf/config.yaml"


local _M = {version = 0.1}


local function read_file(path)
    local file,msg = io_open(path, "rb")   -- read and binary mode
    if not file then
        log.error("read file faild:"..path , msg)
        return nil
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end


function _M.local_conf()
    local yaml_config = read_file(local_conf_path)
    if type(yaml_config) ~= "string" then
        return nil, "failed to read config file"
    end

    return yaml.parse(yaml_config)
end


return _M
