-- Copyright (C) Yuansheng Wang

local ngx = ngx
local pcall = pcall
local yaml = require("apimeta.core.yaml")
local io_open = io.open

local config_path = ngx.config.prefix() .. "conf/config.yaml"

local _M = {}

local function read_file(path)
    local file = io_open(path, "rb")   -- r read mode and b binary mode
    if not file then
        return nil
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end

function _M.read()
    local yaml_config = read_file(config_path)
    if type(yaml_config) ~= "string" then
        return nil, "failed to read config file"
    end

    return yaml.parse(yaml_config)
end

return _M
