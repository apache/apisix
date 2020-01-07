--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local log = require("apisix.core.log")
local yaml = require("tinyyaml")
local ngx = ngx
local io_open = io.open
local io_popen = io.popen
local type = type
local local_conf_path = ngx.config.prefix() .. "conf/config.yaml"
local config_data
local hostname


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


local function shell(cmd)
    local fd, err = io_popen(cmd, "r")
    if not fd then
        return nil, err
    end

    local output = fd:read("*a")
    fd:close()
    return output
end


function _M.init()
    local err
    hostname, err = shell("cat /etc/hostname")
    if not hostname then
        log.error("failed to fetch hostname by shell: ", err)
    end
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
    if type(config_data) == "table" then
        if config_data.apisix and not config_data.apisix.name then
            config_data.apisix.name = hostname
        end
    end

    return config_data
end


return _M
