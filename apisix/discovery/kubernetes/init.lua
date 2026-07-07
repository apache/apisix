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

local ngx = ngx
local type = type
local ipairs = ipairs
local pairs = pairs
local string = string
local error = error
local is_http = ngx.config.subsystem == "http"
local process = require("ngx.process")
local core = require("apisix.core")
local local_conf = require("apisix.core.config_local").local_conf()
local k8s_core = require("apisix.discovery.kubernetes.core")


local ctx

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})


local _M = {
    version = "0.0.1"
}


local function get_endpoint_dict_name(id)
    local shm = "kubernetes"

    if id and type(id) == "string" and #id > 0 then
        shm = shm .. "-" .. id
    end

    if not is_http then
        shm = shm .. "-stream"
    end
    return shm
end


local function get_endpoint_dict(id)
    local dict_name = get_endpoint_dict_name(id)
    return ngx.shared[dict_name]
end


local function single_mode_init(conf)
    local endpoint_dict = get_endpoint_dict()

    if not endpoint_dict then
        error("failed to get lua_shared_dict: ngx.shared.kubernetes, " ..
                "please check your APISIX version")
    end

    if process.type() ~= "privileged agent" then
        ctx = endpoint_dict
        return
    end

    local handle, err = k8s_core.create_handle(conf, {
        endpoint_dict = endpoint_dict,
    })
    if err then
        error(err)
        return
    end

    ctx = handle
    k8s_core.start_fetch(ctx)
end


local function single_mode_nodes(service_name)
    return k8s_core.resolve_nodes(
        endpoint_lrucache, service_name,
        "^(.*):(.*)$",   -- namespace/name:port_name
        function(match)
            return ctx, match[1], match[2]
        end)
end


local function multiple_mode_worker_init(confs)
    for _, conf in ipairs(confs) do

        local id = conf.id
        if ctx[id] then
            error("duplicate id value")
        end

        local endpoint_dict = get_endpoint_dict(id)
        if not endpoint_dict then
            error(string.format("failed to get lua_shared_dict: ngx.shared.kubernetes-%s, ", id) ..
                    "please check your APISIX version")
        end

        ctx[id] = endpoint_dict
    end
end


local function multiple_mode_init(confs)
    ctx = core.table.new(#confs, 0)

    if process.type() ~= "privileged agent" then
        multiple_mode_worker_init(confs)
        return
    end

    for _, conf in ipairs(confs) do
        local id = conf.id

        if ctx[id] then
            error("duplicate id value")
        end

        local endpoint_dict = get_endpoint_dict(id)
        if not endpoint_dict then
            error(string.format("failed to get lua_shared_dict: ngx.shared.kubernetes-%s, ", id) ..
                    "please check your APISIX version")
        end

        local handle, err = k8s_core.create_handle(conf, {
            endpoint_dict = endpoint_dict,
        })
        if err then
            error(err)
            return
        end

        ctx[id] = handle
    end

    for _, item in pairs(ctx) do
        k8s_core.start_fetch(item)
    end
end


local function multiple_mode_nodes(service_name)
    return k8s_core.resolve_nodes(
        endpoint_lrucache, service_name,
        "^(.*)/(.*/.*):(.*)$",   -- id/namespace/name:port_name
        function(match)
            local id = match[1]
            local endpoint_dict = ctx[id]
            if not endpoint_dict then
                core.log.error("id not exist")
                return nil
            end
            return endpoint_dict, match[2], match[3]
        end)
end


function _M.init_worker()
    local discovery_conf = local_conf.discovery.kubernetes
    core.log.info("kubernetes discovery conf: ", core.json.delay_encode(discovery_conf))
    if #discovery_conf == 0 then
        _M.nodes = single_mode_nodes
        single_mode_init(discovery_conf)
    else
        _M.nodes = multiple_mode_nodes
        multiple_mode_init(discovery_conf)
    end
end


function _M.dump_data()
    local discovery_conf = local_conf.discovery.kubernetes
    local eps = {}

    if #discovery_conf == 0 then
        local endpoint_dict = get_endpoint_dict()
        local endpoints = k8s_core.dump_endpoints_from_dict(endpoint_dict)
        if endpoints then
            core.table.insert(eps, {
                endpoints = endpoints
            })
        end
    else
        for _, conf in ipairs(discovery_conf) do
            local endpoint_dict = get_endpoint_dict(conf.id)
            local endpoints = k8s_core.dump_endpoints_from_dict(endpoint_dict)
            if endpoints then
                core.table.insert(eps, {
                    id = conf.id,
                    endpoints = endpoints
                })
            end
        end
    end

    return {config = discovery_conf, endpoints = eps}
end


local function check_ready(id)
    local endpoint_dict = get_endpoint_dict(id)
    if not endpoint_dict then
        core.log.error("failed to get lua_shared_dict:", get_endpoint_dict_name(id),
                       ", please check your APISIX version")
        return false, "failed to get lua_shared_dict: " .. get_endpoint_dict_name(id)
            .. ", please check your APISIX version"
    end
    local ready = endpoint_dict:get("discovery_ready")
    if not ready then
        core.log.warn("kubernetes discovery not ready")
        return false, "kubernetes discovery not ready"
    end
    return true
end


local function single_mode_check_discovery_ready()
    local _, err = check_ready()
    if err then
        return false, err
    end
    return true
end


local function multiple_mode_check_discovery_ready(confs)
    for _, conf in ipairs(confs) do
        local _, err = check_ready(conf.id)
        if err then
            return false, err
        end
    end
    return true
end


function _M.check_discovery_ready()
    local discovery_conf = local_conf.discovery and local_conf.discovery.kubernetes
    if not discovery_conf then
        return true
    end
    if #discovery_conf == 0 then
        return single_mode_check_discovery_ready()
    else
        return multiple_mode_check_discovery_ready(discovery_conf)
    end
end


return _M
