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
local tostring = tostring
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


local function single_mode_nodes(service_name, discovery_args)
    if discovery_args and discovery_args.cluster_ids then
        core.log.error("discovery_args.cluster_ids requires kubernetes discovery ",
                       "configured with multiple clusters, service: ", service_name)
        return nil
    end

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


local function merge_cluster_nodes(endpoint_dicts, endpoint_key, endpoint_port)
    local nodes = {}
    local seen = {}
    for _, endpoint_dict in ipairs(endpoint_dicts) do
        local cluster_nodes = k8s_core.create_endpoint_lrucache(endpoint_dict, endpoint_key,
                                                                endpoint_port)
        for _, node in ipairs(cluster_nodes or {}) do
            local addr = node.host .. ":" .. tostring(node.port)
            if not seen[addr] then
                seen[addr] = true
                core.table.insert(nodes, node)
            end
        end
    end

    return nodes
end


-- with cluster_ids, service_name is "namespace/name:port_name"
local cluster_ids_service_name_pattern = [[^([^/]+/[^/:]+):(.+)$]]


local function parse_cluster_ids_service_name(service_name)
    local match = ngx.re.match(service_name, cluster_ids_service_name_pattern, "jo")
    if not match then
        return nil, "service_name must be namespace/name:port_name when "
                    .. "discovery_args.cluster_ids is set, got: " .. service_name
    end
    return match
end


local function selected_clusters_nodes(service_name, cluster_ids)
    local match, err = parse_cluster_ids_service_name(service_name)
    if not match then
        core.log.error(err)
        return nil
    end
    local endpoint_key, endpoint_port = match[1], match[2]

    local endpoint_dicts = core.table.new(#cluster_ids, 0)
    local versions = core.table.new(#cluster_ids, 0)
    local unknown_ids
    for _, id in ipairs(cluster_ids) do
        local endpoint_dict = ctx[id]
        if not endpoint_dict then
            unknown_ids = unknown_ids or {}
            core.table.insert(unknown_ids, id)
        else
            local endpoint_version = endpoint_dict:get(endpoint_key .. "#version")
            if endpoint_version then
                core.table.insert(endpoint_dicts, endpoint_dict)
                core.table.insert(versions, id .. "#" .. endpoint_version)
            end
        end
    end

    if unknown_ids then
        core.log.warn("skip unknown kubernetes discovery cluster ids: ",
                      core.table.concat(unknown_ids, ", "), ", service: ", service_name)
    end

    if #endpoint_dicts == 0 then
        core.log.info("get empty endpoint version from selected clusters for ", service_name)
        return nil
    end

    return endpoint_lrucache(service_name .. "#" .. core.table.concat(cluster_ids, ","),
                             core.table.concat(versions, ","),
                             merge_cluster_nodes, endpoint_dicts, endpoint_key, endpoint_port)
end


local function multiple_mode_nodes(service_name, discovery_args)
    local cluster_ids = discovery_args and discovery_args.cluster_ids
    if cluster_ids then
        return selected_clusters_nodes(service_name, cluster_ids)
    end

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


function _M.check_discovery_args(discovery_args, service_name, in_dp)
    local cluster_ids = discovery_args and discovery_args.cluster_ids
    if not cluster_ids then
        return true
    end

    if service_name then
        local match, err = parse_cluster_ids_service_name(service_name)
        if not match then
            return false, err
        end
    end

    -- the data plane resolves the ids at runtime, where an unknown id is skipped
    if in_dp then
        return true
    end

    local discovery_conf = local_conf.discovery.kubernetes
    if #discovery_conf == 0 then
        return false, "discovery_args.cluster_ids requires kubernetes discovery "
                      .. "configured with multiple clusters"
    end

    local known_ids = {}
    for _, conf in ipairs(discovery_conf) do
        known_ids[conf.id] = true
    end

    local unknown_ids
    for _, id in ipairs(cluster_ids) do
        if not known_ids[id] then
            unknown_ids = unknown_ids or {}
            core.table.insert(unknown_ids, id)
        end
    end

    if unknown_ids then
        return false, "unknown kubernetes discovery cluster ids in "
                      .. "discovery_args.cluster_ids: " .. core.table.concat(unknown_ids, ", ")
    end

    return true
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
