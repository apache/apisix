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

local core = require("apisix.core")
local nacos_factory = require("apisix.discovery.nacos.factory")
local utils = require("apisix.discovery.nacos.utils")
local process = require("ngx.process")
local ipairs = ipairs
local require = require
local table = require("apisix.core.table")
local pcall = pcall
local local_conf         = require('apisix.core.config_local').local_conf()
local ngx = ngx

local shdict_name = "nacos"
if ngx.config.subsystem == "stream" then
    shdict_name = shdict_name .. "-stream"
end

local nacos_dict = ngx.shared[shdict_name]
local OLD_CONFIG_ID = utils.old_config_id
local _M = {}
local nacos_clients = {}

function _M.nodes(service_name, discovery_args)
    local ns_id = discovery_args and discovery_args.namespace_id or utils.default_namespace_id
    local group_name = discovery_args and discovery_args.group_name or utils.default_group_name
    local id = discovery_args and discovery_args.id or OLD_CONFIG_ID
    local key = utils.generate_key(id,
                                   ns_id,
                                   group_name,
                                   service_name)
    local value = nacos_dict:get_stale(key)
    local nodes = {}
    if not value then
         -- maximum waiting time: 5 seconds
        local waiting_time = 5
        local step = 0.1
        local logged = false
        while not value and waiting_time > 0 do
            if not logged then
                logged = true
            end

            ngx.sleep(step)
            waiting_time = waiting_time - step
            value = nacos_dict:get_stale(key)
        end
    end
    if not value then
        core.log.error("nacos service not found: ", service_name)
        return nodes
    end

    nodes = core.json.decode(value)

    local res = {}
    for _, node in ipairs(nodes) do
        if discovery_args then
            if utils.match_metdata(node.metadata, discovery_args.metadata) then
                core.table.insert(res, node)
            end
        else
            core.table.insert(res, node)
        end
    end

    core.log.info("nacos service_name: ", service_name, " nodes: ", core.json.encode(res))
    return res
end

local function generate_new_config_from_old(discovery_conf)
    local config = {
        id = OLD_CONFIG_ID,
        hosts = discovery_conf.host,
        prefix = discovery_conf.prefix,
        fetch_interval = discovery_conf.fetch_interval,
        auth = {
            access_key = discovery_conf.access_key,
            secret_key = discovery_conf.secret_key,
        },
        default_weight = discovery_conf.weight,
        timeout = discovery_conf.timeout,
        old_conf = true
    }
    return {config}
end

function _M.init_worker()
    local local_conf = require("apisix.core.config_local").local_conf(true)
    local discovery_conf = local_conf.discovery and local_conf.discovery.nacos or {}

    if process.type() ~= "privileged agent" then
        return
    end

    local keep = {}
    -- support old way
    if discovery_conf.host then
        discovery_conf = generate_new_config_from_old(discovery_conf)
    end
    for _, val in ipairs(discovery_conf) do
        local id = val.id
        local version = ngx.md5(core.json.encode(val, true))
        keep[id] = true

        -- The nacos config has not been changed.
        if nacos_clients[id] and nacos_clients[id].version == version then
            goto CONTINUE
        end

        if nacos_clients[id] then
            nacos_clients[id]:stop()
        end
        local new_client = nacos_factory.new(val)
        new_client:start()
        nacos_clients[id] = new_client

        ::CONTINUE::
    end


    for id, client in pairs(nacos_clients) do
        -- The nacos config has been deleted.
        if not keep[client.id] then
            client:stop()
            nacos_clients[id] = nil
        end
    end
end


-- Now we use control plane to list the services
function _M.list_all_services()
    return {}
end


function _M.get_health_checkers()
    local result = core.table.new(0, 4)
    if nacos_clients == nil then
        return result
    end

    for id in pairs(nacos_clients) do
        local health_check = require("resty.healthcheck")
        local list = health_check.get_target_list(id, "nacos")
        if list then
            result[id] = list
        end
    end

    return result
end

local cjson = require "cjson"

function _M.dump_data()
    local applications = {}
    local keys = nacos_dict:get_keys() or {}

    for _, key in ipairs(keys) do
        local parts = {}
        for part in key:gmatch("[^/]+") do
            table.insert(parts, part)
        end

        if #parts == 4 then
            local id, namespace_id,
                  group_name, service_name = parts[1], parts[2], parts[3], parts[4]
            local data_str = nacos_dict:get(key)

            if data_str and data_str ~= "" then
                -- Decode JSON string to Lua table
                local success, data = pcall(cjson.decode, data_str)
                if success then
                    applications[id] = applications[id] or {}
                    applications[id][namespace_id] = applications[id][namespace_id] or {}
                    applications[id][namespace_id][group_name] = applications[id]
                                                                 [namespace_id][group_name] or {}
                    applications[id][namespace_id][group_name][service_name] = data
                else
                    ngx.log(ngx.ERR, "failed to decode data for key ", key, ": ", data)
                end
            end
        end
    end

    return {
        config = local_conf.discovery.nacos,
        services = applications
    }
end

return _M
