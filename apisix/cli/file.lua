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

local yaml = require("tinyyaml")
local env = require("apisix.cli.env")
local profile = require("apisix.core.profile")

local pairs = pairs
local type = type
local open = io.open
local str_find = string.find
local str_gmatch = string.gmatch

local _M = {}


local function tab_is_array(t)
    local count = 0
    for k,v in pairs(t) do
        count = count + 1
    end

    return #t == count
end


local merge_conf
merge_conf = function(base, new_tab)
    for key, val in pairs(new_tab) do
        if type(val) == "table" then
            if tab_is_array(val) then
                base[key] = val
            elseif base[key] == nil then
                base[key] = val
            else
                merge_conf(base[key], val)
            end

        else
            base[key] = val
        end
    end

    return base
end


local function is_empty_yaml_line(line)
    return line == '' or str_find(line, '^%s*$') or str_find(line, '^%s*#')
end


function _M.write_file(file_path, data)
    local file, err = open(file_path, "w+")
    if not file then
        return false, "failed to open file: " .. file_path .. ", error info:" .. err
    end

    local _, err = file:write(data)
    if err ~= nil then
        return false, "failed to write file: " .. file_path .. ", error info:" .. err
    end

    file:close()

    return true
end


function _M.read_file(file_path)
    local file, err = open(file_path, "rb")
    if not file then
        return false, "failed to open file: " .. file_path .. ", error info:" .. err
    end

    local data, err = file:read("*all")
    if err ~= nil then
        return false, "failed to read file: " .. file_path .. ", error info:" .. err
    end

    file:close()
    return data
end


function _M.read_yaml_conf()
    profile.apisix_home = env.apisix_home .. "/"
    local local_conf_path = profile:yaml_path("config-default")

    local default_conf_yaml, err = _M.read_file(local_conf_path)
    if not default_conf_yaml then
        return nil, err
    end

    local default_conf = yaml.parse(default_conf_yaml)
    if not default_conf then
        return nil, "invalid config-default.yaml file"
    end

    local_conf_path = profile:yaml_path("config")
    local user_conf_yaml, err = _M.read_file(local_conf_path)
    if not user_conf_yaml then
        return nil, err
    end

    local is_empty_file = true
    for line in str_gmatch(user_conf_yaml .. '\n', '(.-)\r?\n') do
        if not is_empty_yaml_line(line) then
            is_empty_file = false
            break
        end
    end

    if not is_empty_file then
        local user_conf = yaml.parse(user_conf_yaml)
        if not user_conf then
            return nil, "invalid config.yaml file"
        end

        merge_conf(default_conf, user_conf)
    end

    return default_conf
end


function _M.is_file_exist(file_path)
    local file, err = open(file_path)
    if not file then
        return false, "failed to open file: " .. file_path .. ", error info: " .. err
    end

    file:close()
    return true
end


return _M
