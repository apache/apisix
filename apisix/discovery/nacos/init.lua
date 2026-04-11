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
local math_random        = math.random
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local log                = core.log

local default_weight
local nacos_dict = ngx.shared.nacos
if not nacos_dict then
    error("lua_shared_dict \"nacos\" not configured")
end

local access_key
local secret_key

local _M = {}


local function get_key(namespace_id, group_name, service_name)
    return namespace_id .. '.' .. group_name .. '.' .. service_name
end


local function get_base_uri_by_index(index)
    local host = local_conf.discovery.nacos.host

    local url = host[index]
    if not url then
        return nil
    end

    return nacos_client.build_base_uri(url, local_conf.discovery.nacos.prefix)
end


local curr_service_in_use = {}


local function fetch_full_registry(premature)
    if premature then
        return
    end

    local infos = nacos_client.get_nacos_services()
    if #infos == 0 then
        return
    end

    local host_list = local_conf.discovery.nacos.host
    local host_count = #host_list
    local start = math_random(host_count)

    local timeout = local_conf.discovery.nacos.timeout

    for i = 0, host_count - 1 do
        local idx = (start + i - 1) % host_count + 1
        local base_uri, username, password = get_base_uri_by_index(idx)

        if not base_uri then
            log.warn('nacos host at index ', idx, ' is invalid, skip')
        else
            local nodes_cache, service_names, err = nacos_client.fetch_from_host(
                base_uri, username, password, infos, {
                    default_weight = default_weight,
                    access_key = access_key,
                    secret_key = secret_key,
                    timeout = timeout,
                })
            if nodes_cache then
                for key, nodes in pairs(nodes_cache) do
                    local content = core.json.encode(nodes)
                    nacos_dict:set(key, content)
                end

                for key, _ in pairs(curr_service_in_use) do
                    if not service_names[key] then
                        nacos_dict:delete(key)
                    end
                end
                curr_service_in_use = service_names
                return
            end
            log.error('fetch_from_host: ', base_uri, ' err:', err)
        end
    end

    log.error('failed to fetch nacos registry from all hosts')
end


function _M.nodes(service_name, discovery_args)
    local namespace_id = discovery_args and
            discovery_args.namespace_id or "public"
    local group_name = discovery_args
            and discovery_args.group_name or "DEFAULT_GROUP"
    local key = get_key(namespace_id, group_name, service_name)
    local value = nacos_dict:get(key)
    if not value then
        core.log.error("nacos service not found: ", service_name)
        return nil
    end
    local nodes = core.json.decode(value)
    return nodes
end


function _M.init_worker()
    default_weight = local_conf.discovery.nacos.weight
    log.info('default_weight:', default_weight)
    local fetch_interval = local_conf.discovery.nacos.fetch_interval
    log.info('fetch_interval:', fetch_interval)
    access_key = local_conf.discovery.nacos.access_key
    secret_key = local_conf.discovery.nacos.secret_key
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


function _M.dump_data()
    local keys = nacos_dict:get_keys(0)
    local applications = {}
    for _, key in ipairs(keys) do
        local value = nacos_dict:get(key)
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
