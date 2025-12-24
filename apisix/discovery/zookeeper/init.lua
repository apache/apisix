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
local utils = require("apisix.discovery.zookeeper.utils")
local lrucache = require("resty.lrucache")
local table = require("apisix.core.table")
local local_conf = require("apisix.core.config_local").local_conf()
local ngx = ngx
local ipairs = ipairs
local log = core.log

local _M = {
    version = "0.0.1",
}

-- Global Configuration
local zookeeper_conf
-- Service Instance Cache（service_name -> {nodes, expire_time}）
local instance_cache = lrucache.new(1024)

-- Timer Identifier
local fetch_timer

-- The instance list of a single service from ZooKeeper
local function fetch_service_instances(conf, service_name)
    -- 1. Init connect
    local client, err = utils.new_zk_client(conf)
    if not client then
        return nil, err
    end

    -- 2. Create path
    local service_path = conf.root_path .. "/" .. service_name
    local ok, err = utils.create_zk_path(client, service_path)
    if not ok then
        utils.close_zk_client(client)
        return nil, err
    end

    -- 3. All instance nodes under a service
    local children, err = client:get_children(service_path)
    if not children then
        utils.close_zk_client(client)
        if err == "not exists" then
            log.warn("service path not exists: ", service_path)
            return {}
        end
        log.error("get zk children failed: ", err)
        return nil, err
    end

    -- 4. Parse the data of each instance node one by one
    local instances = {}
    for _, child in ipairs(children) do
        local instance_path = service_path .. "/" .. child
        local data, stat, err = client:get_data(instance_path)
        do
            if not data then
                log.error("get instance data failed: ", instance_path, "stat: ", stat, "err: ", err)
                break
            end

            -- Parse instance data
            local instance = utils.parse_instance_data(data)
            if instance then
                table.insert(instances, instance)
            end
        end
    end

    -- 5. Close connects
    utils.close_zk_client(client)

    log.debug("fetch service instances: ", service_name, " count: ", #instances)
    return instances
end

-- Scheduled fetch of all service instances (full cache update)）
local function fetch_all_services()
    if not zookeeper_conf then
        log.warn("zookeeper discovery config not loaded")
        return
    end

    -- 1. Init Zookeeper client
    local client, err = utils.new_zk_client(zookeeper_conf)
    if not client then
        log.error("init zk client failed: ", err)
        return
    end

    -- 2.  Check instance root path exist
    local ex, err = client:exists(zookeeper_conf.root_path)
    if ex == false then
        local parent, cerr = client:create(zookeeper_conf.root_path, "", "persistent", false)
        if not parent then
           utils.close_zk_client(client)
           log.error("failed to create parent: ", cerr)
        end
    elseif err then
        utils.close_zk_client(client)
        log.error("exist zk root failed: ", err)
        return
    end

    -- 3.  All instance nodes under a service
    local services, err = client:get_children(zookeeper_conf.root_path)
    if not services then
        utils.close_zk_client(client)
        log.error("get zk root children failed: ", err)
        return
    end

    -- 4. Fetch the instances of each service and update the cache
    local now = ngx.time()
    for _, service in ipairs(services) do
        local instances, err = fetch_service_instances(zookeeper_conf, service)
        if instances then
            instance_cache:set(service, {
                nodes = instances,
            }, now + zookeeper_conf.cache_ttl)
        else
            log.error("fetch service instances failed: ", service, " err: ", err)
        end
    end

    -- 5. Close connects
    utils.close_zk_client(client)
end

function _M.nodes(service_name)
    if not service_name or service_name == "" then
        log.error("service name is empty")
        return nil
    end

    -- 1. Check instance_cache initialized
    if not instance_cache then
        log.error("instance_cache not initialized")
        return nil
    end

    -- 2. Get from cache
    local cache, _, _ = instance_cache:get(service_name)
    local now = ngx.time()

    -- 3. If the cache is missed or expired, actively pull (the data)）
    if not cache or cache.expire_time < now then
        log.debug("cache miss or expired, fetch from zk: ", service_name)
        local instances, err = fetch_service_instances(zookeeper_conf, service_name)
        if not instances then
            log.error("fetch instances failed: ", service_name, " err: ", err)
            -- Fallback: Return the old cache (if available)）
            if cache then
                return cache.nodes
            end
            return nil
        end

        -- Update the cache
        cache = {
            nodes = instances,
        }

        instance_cache:set(service_name, cache, now + zookeeper_conf.cache_ttl)
    end

    return cache.nodes
end

function _M.init_worker()
    -- Load configuration
    zookeeper_conf = local_conf.discovery and local_conf.discovery.zookeeper or {}
    log.info("zookeeper_conf:", core.json.encode(zookeeper_conf))

    -- Start the timer
    if not fetch_timer then
        fetch_timer = ngx.timer.every(zookeeper_conf.fetch_interval, fetch_all_services)
        log.info("zk discovery fetch timer started, interval: ", zookeeper_conf.fetch_interval, "s")
    end

    -- Manually execute a full pull immediately
    ngx.timer.at(0, fetch_all_services)
end

function _M.dump_data()
    local keys = instance_cache:get_keys(0)
    local applications = {}
    for _, key in ipairs(keys) do
        local value, _, _ = instance_cache:get(key)
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

function _M.destroy()
    if fetch_timer then
        fetch_timer = nil
    end
    instance_cache:flush_all()
    log.info("zookeeper discovery destroyed")
end

return _M
