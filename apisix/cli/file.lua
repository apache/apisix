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
local profile = require("apisix.core.profile")
local util = require("apisix.cli.util")
local dkjson = require("dkjson")

local pairs = pairs
local type = type
local tonumber = tonumber
local getmetatable = getmetatable
local getenv = os.getenv
local str_gmatch = string.gmatch
local str_find = string.find
local str_sub = string.sub
local print = print

local _M = {}
local exported_vars


function _M.get_exported_vars()
    return exported_vars
end


local function is_empty_yaml_line(line)
    return line == '' or str_find(line, '^%s*$') or str_find(line, '^%s*#')
end


local function tab_is_array(t)
    local count = 0
    for k, v in pairs(t) do
        count = count + 1
    end

    return #t == count
end


local function resolve_conf_var(conf)
    for key, val in pairs(conf) do
        if type(val) == "table" then
            local ok, err = resolve_conf_var(val)
            if not ok then
                return nil, err
            end

        elseif type(val) == "string" then
            local err
            local var_used = false
            -- we use '${{var}}' because '$var' and '${var}' are taken
            -- by Nginx
            local new_val = val:gsub("%$%{%{%s*([%w_]+[%:%=]?.-)%s*%}%}", function(var)
                local i, j = var:find("%:%=")
                local default
                if i and j then
                    default = var:sub(i + 2, #var)
                    default = default:gsub('^%s*(.-)%s*$', '%1')
                    var = var:sub(1, i - 1)
                end

                local v = getenv(var) or default
                if v then
                    if not exported_vars then
                        exported_vars = {}
                    end

                    exported_vars[var] = v
                    var_used = true
                    return v
                end

                err = "failed to handle configuration: " ..
                      "can't find environment variable " .. var
                return ""
            end)

            if err then
                return nil, err
            end

            if var_used then
                if tonumber(new_val) ~= nil then
                    new_val = tonumber(new_val)
                elseif new_val == "true" then
                    new_val = true
                elseif new_val == "false" then
                    new_val = false
                end
            end

            conf[key] = new_val
        end
    end

    return true
end


_M.resolve_conf_var = resolve_conf_var


local function replace_by_reserved_env_vars(conf)
    -- TODO: support more reserved environment variables
    local v = getenv("APISIX_DEPLOYMENT_ETCD_HOST")
    if v and conf["deployment"] and conf["deployment"]["etcd"] then
        local val, _, err = dkjson.decode(v)
        if err or not val then
            print("parse ${APISIX_DEPLOYMENT_ETCD_HOST} failed, error:", err)
            return
        end

        conf["deployment"]["etcd"]["host"] = val
    end
end


local function tinyyaml_type(t)
    local mt = getmetatable(t)
    if mt then
        return mt.__type
    end
end


local function path_is_multi_type(path, type_val)
    if str_sub(path, 1, 14) == "nginx_config->" and
            (type_val == "number" or type_val == "string") then
        return true
    end

    if path == "apisix->node_listen" and type_val == "number" then
        return true
    end

    if path == "apisix->ssl->key_encrypt_salt" then
        return true
    end

    return false
end


local function merge_conf(base, new_tab, ppath)
    ppath = ppath or ""

    for key, val in pairs(new_tab) do
        if type(val) == "table" then
            if tinyyaml_type(val) == "null" then
                base[key] = nil

            elseif tab_is_array(val) then
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
            local type_val = type(val)

            if base[key] == nil then
                base[key] = val
            elseif type(base[key]) ~= type_val then
                local path = ppath == "" and key or ppath .. "->" .. key

                if path_is_multi_type(path, type_val) then
                    base[key] = val
                else
                    return nil, "failed to merge, path[" .. path ..  "] expect: " ..
                                type(base[key]) .. ", but got: " .. type_val
                end
            else
                base[key] = val
            end
        end
    end

    return base
end


function _M.read_yaml_conf(apisix_home)
    if apisix_home then
        profile.apisix_home = apisix_home .. "/"
    end

    local local_conf_path = profile:yaml_path("config-default")
    local default_conf_yaml, err = util.read_file(local_conf_path)
    if not default_conf_yaml then
        return nil, err
    end

    local default_conf = yaml.parse(default_conf_yaml)
    if not default_conf then
        return nil, "invalid config-default.yaml file"
    end

    local_conf_path = profile:yaml_path("config")
    local user_conf_yaml, err = util.read_file(local_conf_path)
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

        local ok, err = resolve_conf_var(user_conf)
        if not ok then
            return nil, err
        end

        ok, err = merge_conf(default_conf, user_conf)
        if not ok then
            return nil, err
        end
    end

    if default_conf.deployment then
        default_conf.deployment.config_provider = "etcd"
        if default_conf.deployment.role == "traditional" then
            default_conf.etcd = default_conf.deployment.etcd

        elseif default_conf.deployment.role == "control_plane" then
            default_conf.etcd = default_conf.deployment.etcd
            default_conf.apisix.enable_admin = true

        elseif default_conf.deployment.role == "data_plane" then
            if default_conf.deployment.role_data_plane.config_provider == "yaml" then
                default_conf.deployment.config_provider = "yaml"
            elseif default_conf.deployment.role_data_plane.config_provider == "xds" then
                default_conf.deployment.config_provider = "xds"
            else
                default_conf.etcd = default_conf.deployment.role_data_plane.control_plane
            end
            default_conf.apisix.enable_admin = false
        end

        if default_conf.etcd and default_conf.deployment.certs then
            -- copy certs configuration to keep backward compatible
            local certs = default_conf.deployment.certs
            local etcd = default_conf.etcd
            if not etcd.tls then
                etcd.tls = {}
            end
            etcd.tls.cert = certs.cert
            etcd.tls.key = certs.cert_key
        end
    end

    if default_conf.deployment.config_provider == "yaml" then
        local apisix_conf_path = profile:yaml_path("apisix")
        local apisix_conf_yaml, _ = util.read_file(apisix_conf_path)
        if apisix_conf_yaml then
            local apisix_conf = yaml.parse(apisix_conf_yaml)
            if apisix_conf then
                local ok, err = resolve_conf_var(apisix_conf)
                if not ok then
                    return nil, err
                end
            end
        end
    end

    replace_by_reserved_env_vars(default_conf)

    return default_conf
end


return _M
