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

local require            = require
local local_conf         = require('apisix.core.config_local').local_conf()
local core               = require('apisix.core')
local nacos_client       = require('apisix.discovery.nacos.client')
local ipairs             = ipairs
local pairs              = pairs
local error              = error
local math_random        = math.random
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local log                = core.log

local _M = {}

local nacos_dict
local registries = {}


local function get_dict()
    if not nacos_dict then
        nacos_dict = ngx.shared.nacos
    end
    return nacos_dict
end


local function default_key_builder(id)
    return function(namespace_id, group_name, service_name)
        return id .. "/" .. namespace_id .. "/" .. group_name .. "/" .. service_name
    end
end


local function fetch_full_registry(premature, reg)
    if premature or reg.stop_flag then
        return
    end

    local dict = get_dict()
    if not dict then
        log.error("nacos shared dict not available")
        return
    end

    local services = reg.service_scanner()
    if reg.stop_flag then
        return
    end

    local prefix = reg.id .. "/"

    if #services == 0 then
        local all_keys = dict:get_keys(0)
        for _, key in ipairs(all_keys) do
            if core.string.has_prefix(key, prefix) then
                dict:delete(key)
            end
        end
        if not reg.stop_flag then
            ngx_timer_at(reg.conf.fetch_interval or 30, fetch_full_registry, reg)
        end
        return
    end

    local hosts = reg.conf.host
    local host_count = #hosts
    local start = math_random(host_count)
    local timeout = reg.conf.timeout

    for i = 0, host_count - 1 do
        if reg.stop_flag then
            return
        end

        local idx = (start + i - 1) % host_count + 1
        local base_uri, username, password = nacos_client.build_base_uri(
            hosts[idx], reg.conf.prefix)

        if not base_uri then
            log.warn("nacos host at index ", idx, " is invalid, skip")
        else
            local nodes_cache, service_names, err = nacos_client.fetch_from_host(
                base_uri,
                username or reg.username,
                password or reg.password,
                services, {
                    default_weight    = reg.conf.weight,
                    access_key        = reg.conf.access_key,
                    secret_key        = reg.conf.secret_key,
                    timeout           = timeout,
                    preserve_metadata = reg.preserve_metadata,
                    key_builder       = reg.key_builder,
                })

            if nodes_cache then
                if reg.stop_flag then
                    return
                end

                for key, nodes in pairs(nodes_cache) do
                    dict:set(key, core.json.encode(nodes))
                end

                local all_keys = dict:get_keys(0)
                for _, key in ipairs(all_keys) do
                    if core.string.has_prefix(key, prefix)
                            and not service_names[key] then
                        dict:delete(key)
                    end
                end

                if not reg.stop_flag then
                    ngx_timer_at(reg.conf.fetch_interval or 30,
                                 fetch_full_registry, reg)
                end
                return
            end
            log.error("fetch_from_host: ", base_uri, " err: ", err)
        end
    end

    log.error("failed to fetch nacos registry from all hosts, id: ", reg.id)
    if not reg.stop_flag then
        ngx_timer_at(reg.conf.fetch_interval or 30, fetch_full_registry, reg)
    end
end


-- ─── Registry management API ──────────────────────────────────────────

--- Create a nacos registry instance.
---
--- conf fields: id, host (array), fetch_interval, prefix, weight,
---              access_key, secret_key, timeout ({connect,send,read} in ms)
---
--- options: service_scanner (function), preserve_metadata (bool),
---          key_builder (function(ns,group,svc)->string),
---          username (string), password (string)
function _M.create_registry(conf, options)
    options = options or {}
    local id = conf.id
    local reg = {
        id              = id,
        conf            = conf,
        stop_flag       = false,
        preserve_metadata = options.preserve_metadata or false,
        key_builder     = options.key_builder or default_key_builder(id),
        service_scanner = options.service_scanner or function()
            return nacos_client.get_nacos_services()
        end,
        username        = options.username,
        password        = options.password,
    }

    registries[id] = reg
    return reg
end


function _M.start_registry(reg)
    ngx_timer_at(0, fetch_full_registry, reg)
end


function _M.stop_registry(id)
    local reg = registries[id]
    if not reg then
        return
    end

    reg.stop_flag = true
    registries[id] = nil

    local dict = get_dict()
    if dict then
        local prefix = id .. "/"
        local all_keys = dict:get_keys(0)
        for _, key in ipairs(all_keys) do
            if core.string.has_prefix(key, prefix) then
                dict:delete(key)
            end
        end
    end
end


function _M.get_registry(id)
    return registries[id]
end


-- ─── Standard discovery interface ─────────────────────────────────────

function _M.nodes(service_name, discovery_args)
    local dict = get_dict()
    if not dict then
        return nil
    end

    local namespace_id = discovery_args and
            discovery_args.namespace_id or "public"
    local group_name = discovery_args
            and discovery_args.group_name or "DEFAULT_GROUP"
    local key = "default/" .. namespace_id .. "/" .. group_name .. "/" .. service_name
    local value = dict:get(key)
    if not value then
        core.log.error("nacos service not found: ", service_name)
        return nil
    end
    return core.json.decode(value)
end


function _M.init_worker()
    local dict = ngx.shared.nacos
    if not dict then
        error('lua_shared_dict "nacos" not configured')
    end

    nacos_dict = dict

    local nacos_conf = local_conf.discovery and local_conf.discovery.nacos
    if not nacos_conf then
        return
    end

    -- shallow copy to avoid mutating cached config
    local conf = {}
    for k, v in pairs(nacos_conf) do
        conf[k] = v
    end
    conf.id = "default"
    local reg = _M.create_registry(conf)
    _M.start_registry(reg)
end


function _M.dump_data()
    local dict = get_dict()
    if not dict then
        return {services = {}}
    end

    local keys = dict:get_keys(0)
    local applications = {}
    for _, key in ipairs(keys) do
        local value = dict:get(key)
        if value then
            local nodes = core.json.decode(value)
            if nodes then
                applications[key] = {
                    nodes = nodes,
                }
            end
        end
    end
    return {services = applications or {}}
end


return _M
