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
local profile = require("apisix.core.profile")
local table = require("apisix.core.table")
local yaml = require("tinyyaml")

local io_open = io.open
local type = type
local str_gmatch = string.gmatch
local string = string
local pairs = pairs
local getmetatable = getmetatable


local local_default_conf_path = profile:yaml_path("config-default")
local local_conf_path = profile:yaml_path("config")
local config_data


local _M = {}


local function read_file(path)
    local file, err = io_open(path, "rb")   -- read as binary mode
    if not file then
        log.error("failed to read config file:" .. path, ", error info:", err)
        return nil, err
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end

function _M.clear_cache()
    config_data = nil
end


local function is_empty_yaml_line(line)
    return line == '' or string.find(line, '^%s*$') or
           string.find(line, '^%s*#')
end


local function tinyyaml_type(t)
    local mt = getmetatable(t)
    if mt then
        log.debug("table type: ", mt.__type)
        return mt.__type
    end
end


local function merge_conf(base, new_tab, ppath)
    ppath = ppath or ""

    for key, val in pairs(new_tab) do
        if type(val) == "table" then
            if tinyyaml_type(val) == "null" then
                base[key] = nil

            elseif table.isarray(val) then
                base[key] = val

            else
                if base[key] == nil then
                    base[key] = {}
                end

                local ok, err = merge_conf(
                    base[key],
                    val,
                    ppath == "" and key or ppath .. "->" .. key
                )
                if not ok then
                    return nil, err
                end
            end
        else
            if base[key] == nil then
                base[key] = val
            elseif type(base[key]) ~= type(val) then
                return false, "failed to merge, path[" ..
                              (ppath == "" and key or ppath .. "->" .. key) ..
                              "] expect: " ..
                              type(base[key]) .. ", but got: " .. type(val)
            else
                base[key] = val
            end
        end
    end

    return base
end


function _M.local_conf(force)
    if not force and config_data then
        return config_data
    end

    local default_conf_yaml, err = read_file(local_default_conf_path)
    if type(default_conf_yaml) ~= "string" then
        return nil, "failed to read config-default file:" .. err
    end
    config_data = yaml.parse(default_conf_yaml)

    local user_conf_yaml = read_file(local_conf_path) or ""
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

        config_data, err = merge_conf(config_data, user_conf)
        if err then
            return nil, err
        end
    end

    return config_data
end


return _M
