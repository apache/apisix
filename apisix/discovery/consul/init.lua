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
local local_conf         = require("apisix.core.config_local").local_conf()
local core               = require("apisix.core")
local core_sleep         = require("apisix.core.utils").sleep
local consul_client      = require("apisix.discovery.consul.client")
local util               = require("apisix.cli.util")
local ipairs             = ipairs
local pairs              = pairs
local next               = next
local error              = error
local ngx                = ngx
local tonumber           = tonumber
local ngx_timer_at       = ngx.timer.at
local log                = core.log
local json_delay_encode  = core.json.delay_encode
local process            = require("ngx.process")
local ngx_worker_id      = ngx.worker.id
local exiting            = ngx.worker.exiting
local thread_spawn       = ngx.thread.spawn
local thread_wait        = ngx.thread.wait
local thread_kill        = ngx.thread.kill
local math_random        = math.random
local is_http            = ngx.config.subsystem == "http"

local _M = {
    version = 0.3,
}

local registries = {}
local consul_dict
local dict_name = is_http and "consul" or "consul-stream"

-- Per-worker LRU cache: avoids shared dict access on every request.
local nodes_cache = core.lrucache.new({
    ttl = 1,
    count = 1024,
    invalid_stale = true,
    neg_ttl = 1,
    neg_count = 64,
})

local default_skip_services = {"consul"}
local default_random_range = 5


local function get_dict()
    if not consul_dict then
        consul_dict = ngx.shared[dict_name]
    end
    return consul_dict
end


local function default_key_builder(id)
    return function(service_name)
        return id .. "/" .. service_name
    end
end


-- ─── shared dict operations ───────────────────────────────────────────

local function update_all_services(reg, consul_server_url, up_services)
    local dict = get_dict()
    if not dict then
        return
    end

    local i = 0
    for k, v in pairs(up_services) do
        local content, err = core.json.encode(v)
        if content then
            local ok, set_err, forcible = dict:set(k, content)
            if not ok then
                log.error("failed to set nodes for service: ", k, ", error: ", set_err,
                          ", please consider increasing lua_shared_dict consul size")
            elseif forcible then
                log.warn("consul shared dict is full, forcibly evicting items while ",
                         "setting nodes for service: ", k,
                         ", please consider increasing lua_shared_dict consul size")
            end
        else
            log.error("failed to encode nodes for service: ", k, ", error: ", err)
        end
        i = i + 1
        if i % 100 == 0 then
            ngx.sleep(0)
        end
    end

    local old_services = reg.consul_services[consul_server_url] or {}
    for k, _ in pairs(old_services) do
        if not up_services[k] then
            dict:delete(k)
        end
    end

    reg.consul_services[consul_server_url] = up_services
    log.info("consul registry updated, id: ", reg.id, ", services: ", i)
end


-- ─── dump file operations ─────────────────────────────────────────────

local function read_dump_services(reg)
    if not reg.dump_params then
        return
    end

    local data, err = util.read_file(reg.dump_params.path)
    if not data then
        log.error("read dump file get error: ", err)
        return
    end

    log.info("read dump file: ", data)
    data = util.trim(data)
    if #data == 0 then
        log.error("dump file is empty")
        return
    end

    local entity, err = core.json.decode(data)
    if not entity then
        log.error("decoded dump data got error: ", err, ", file content: ", data)
        return
    end

    if not entity.services or not entity.last_update then
        log.warn("decoded dump data miss fields, file content: ", data)
        return
    end

    local now_time = ngx.time()
    log.info("dump file last_update: ", entity.last_update, ", dump_params.expire: ",
        reg.dump_params.expire, ", now_time: ", now_time)
    if reg.dump_params.expire ~= 0
            and (entity.last_update + reg.dump_params.expire) < now_time then
        log.warn("dump file: ", reg.dump_params.path, " had expired, ignored it")
        return
    end

    local dict = get_dict()
    if not dict then
        return
    end

    for k, v in pairs(entity.services) do
        local content, json_err = core.json.encode(v)
        if content then
            dict:set(reg.key_builder(k), content)
        else
            log.error("failed to encode dump service: ", k, ", error: ", json_err)
        end
    end
    log.info("load dump file into shared dict success")
end


local function write_dump_services(premature, reg)
    if premature then
        return
    end

    if not reg.dump_params then
        return
    end

    -- build services from the tracking table using bare service names for dump
    local services = core.table.new(0, 8)
    local prefix = reg.id .. "/"
    for _, svcs in pairs(reg.consul_services) do
        for k, v in pairs(svcs) do
            -- strip prefix for dump file compatibility
            local bare_key = k
            if core.string.has_prefix(k, prefix) then
                bare_key = k:sub(#prefix + 1)
            end
            services[bare_key] = v
        end
    end

    local entity = {
        services = services,
        last_update = ngx.time(),
        expire = reg.dump_params.expire,
    }
    local data = core.json.encode(entity)
    local succ, err = util.write_file(reg.dump_params.path, data)
    if not succ then
        log.error("write dump into file got error: ", err)
    end
end


local function show_dump_file(reg)
    if not reg or not reg.dump_params then
        return 503, "dump params is nil"
    end

    local data, err = util.read_file(reg.dump_params.path)
    if not data then
        return 503, err
    end

    return 200, data
end


-- ─── polling loop ─────────────────────────────────────────────────────

local function check_keepalive(reg, consul_server, retry_delay)
    if reg.stop_flag then
        return
    end

    if exiting() then
        return
    end

    if consul_server.keepalive then
        local ok, err = ngx_timer_at(0, _M.connect, reg, consul_server, retry_delay)
        if not ok then
            log.error("create ngx_timer_at got error: ", err)
            return
        end
    else
        -- self-rescheduling poll: use timer.at instead of timer.every
        -- so stop_flag can actually halt future wakeups
        local ok, err = ngx_timer_at(consul_server.fetch_interval,
                                     _M.connect, reg, consul_server, retry_delay)
        if not ok then
            log.error("create ngx_timer_at got error: ", err)
            return
        end
    end
end


function _M.connect(premature, reg, consul_server, retry_delay)
    if premature or reg.stop_flag then
        return
    end

    local catalog_thread, spawn_catalog_err = thread_spawn(consul_client.watch_catalog,
                                                           consul_server)
    if not catalog_thread then
        local random_delay = math_random(default_random_range)
        log.error("failed to spawn thread watch catalog: ", spawn_catalog_err,
            ", retry connecting consul after ", random_delay, " seconds")
        core_sleep(random_delay)

        check_keepalive(reg, consul_server, retry_delay)
        return
    end

    local health_thread, err = thread_spawn(consul_client.watch_health, consul_server)
    if not health_thread then
        thread_kill(catalog_thread)
        local random_delay = math_random(default_random_range)
        log.error("failed to spawn thread watch health: ", err,
            ", retry connecting consul after ", random_delay, " seconds")
        core_sleep(random_delay)

        check_keepalive(reg, consul_server, retry_delay)
        return
    end

    local thread_wait_ok, watch_type, index = thread_wait(catalog_thread, health_thread)
    thread_kill(catalog_thread)
    thread_kill(health_thread)
    if not thread_wait_ok then
        local random_delay = math_random(default_random_range)
        log.error("failed to wait thread: ", watch_type, ", retry connecting consul after ",
                random_delay, " seconds")
        core_sleep(random_delay)

        check_keepalive(reg, consul_server, retry_delay)
        return
    end

    if not consul_client.watch_result_is_valid(tonumber(watch_type),
            tonumber(index), consul_server.catalog_index, consul_server.health_index) then
        retry_delay = consul_client.get_retry_delay(retry_delay)
        log.warn("get all svcs got err, retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        check_keepalive(reg, consul_server, retry_delay)
        return
    end

    if reg.stop_flag then
        return
    end

    local up_services, fetch_err, new_catalog_index, new_health_index =
        consul_client.fetch_services_from_server(consul_server, {
            default_weight    = reg.conf.weight,
            sort_type         = reg.conf.sort_type,
            skip_service_map  = reg.skip_service_map,
            preserve_metadata = reg.preserve_metadata,
            key_builder       = reg.key_builder,
        })

    if fetch_err then
        retry_delay = consul_client.get_retry_delay(retry_delay)
        log.warn("get all svcs got err: ", fetch_err,
                 ", retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        check_keepalive(reg, consul_server, retry_delay)
        return
    end

    if reg.stop_flag then
        return
    end

    -- Always call update_all_services to clean up stale keys even when
    -- up_services is empty (e.g., all Consul services deleted).
    update_all_services(reg, consul_server.consul_server_url, up_services)

    if reg.dump_params then
        ngx_timer_at(0, write_dump_services, reg)
    end

    consul_client.update_index(consul_server, new_catalog_index, new_health_index)
    check_keepalive(reg, consul_server, retry_delay)
end


-- ─── Registry management API ──────────────────────────────────────────

--- Create a consul registry instance.
---
--- conf fields: id, servers (array of URLs), token, timeout, weight,
---              keepalive, fetch_interval, sort_type, skip_services,
---              dump, default_service, shared_size
---
--- options: service_scanner (function), preserve_metadata (bool),
---          key_builder (function(service_name) -> string)
function _M.create_registry(conf, options)
    options = options or {}
    local id = conf.id
    if not id or id == "" then
        return nil, "registry id is required"
    end

    if registries[id] then
        _M.stop_registry(id)
    end

    -- build skip service map
    local skip_map = core.table.new(0, 1)
    if conf.skip_services then
        for _, v in ipairs(conf.skip_services) do
            skip_map[v] = true
        end
    end
    for _, v in ipairs(default_skip_services) do
        skip_map[v] = true
    end

    -- clone default_service to avoid mutating the caller's table
    local default_svc
    if conf.default_service then
        default_svc = {}
        for k, v in pairs(conf.default_service) do
            default_svc[k] = v
        end
        default_svc.weight = conf.weight
    end

    local reg = {
        id                = id,
        conf              = conf,
        stop_flag         = false,
        preserve_metadata = options.preserve_metadata or false,
        key_builder       = options.key_builder or default_key_builder(id),
        service_scanner   = options.service_scanner or consul_client.get_consul_services,
        skip_service_map  = skip_map,
        default_service   = default_svc,
        dump_params       = conf.dump,
        consul_services   = core.table.new(0, 1),
    }

    registries[id] = reg
    return reg
end


function _M.start_registry(reg)
    local dict = get_dict()
    if not dict then
        error('lua_shared_dict "' .. dict_name .. '" not configured')
    end

    -- flush stale data for this registry
    local prefix = reg.id .. "/"
    local all_keys = dict:get_keys(0)
    for _, key in ipairs(all_keys) do
        if core.string.has_prefix(key, prefix) then
            dict:delete(key)
        end
    end

    -- load dump file if configured
    if reg.dump_params and reg.dump_params.load_on_init then
        read_dump_services(reg)
    end

    local consul_servers_list, err = consul_client.format_consul_params(reg.conf)
    if err then
        error("format consul config got error: " .. err)
    end
    log.info("consul_server_list: ", json_delay_encode(consul_servers_list, true))

    for _, server in ipairs(consul_servers_list) do
        local ok, timer_err = ngx_timer_at(0, _M.connect, reg, server)
        if not ok then
            error("create consul got error: " .. timer_err)
        end
    end
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


-- ─── Shared helpers ──────────────────────────────────────────────────

local function match_metadata(node_metadata, upstream_metadata)
    if upstream_metadata == nil then
        return true
    end

    if not node_metadata then
        node_metadata = {}
    end

    for k, v in pairs(upstream_metadata) do
        if not node_metadata[k] or node_metadata[k] ~= v then
            return false
        end
    end

    return true
end


local function fetch_nodes_from_shdict(key)
    local dict = get_dict()
    if not dict then
        return nil, "consul shared dict not available"
    end

    local value = dict:get(key)
    if not value then
        return nil, "consul service not found: " .. key
    end

    local nodes, err = core.json.decode(value)
    if not nodes then
        return nil, "failed to decode nodes for key: " .. key
                    .. ", error: " .. (err or "")
    end

    return nodes
end


function _M.get_nodes(key, metadata)
    local nodes, err = nodes_cache(key, nil, fetch_nodes_from_shdict, key)
    if not nodes then
        log.error("fetch nodes failed for key: ", key, ", error: ", err)
        return nil
    end

    if not metadata then
        return nodes
    end

    local res = {}
    for _, node in ipairs(nodes) do
        if match_metadata(node.metadata, metadata) then
            core.table.insert(res, node)
        end
    end
    return res
end


-- ─── Standard discovery interface ─────────────────────────────────────

function _M.nodes(service_name)
    local default_reg = registries["default"]
    local default_svc = default_reg and default_reg.default_service

    -- reuse the cached fetch with "default/" prefix for BC
    local nodes, err = nodes_cache("default/" .. service_name, nil,
                                   fetch_nodes_from_shdict,
                                   "default/" .. service_name)
    if not nodes then
        log.error("fetch nodes failed by ", service_name, ", error: ", err)
        return default_svc and {default_svc}
    end

    log.info("process id: ", ngx_worker_id(), ", [", service_name, "] = ",
        json_delay_encode(nodes, true))

    return nodes
end


-- Used only by dump_data() for diagnostic purposes; not a hot path.
function _M.all_nodes()
    local dict = get_dict()
    if not dict then
        return {}
    end

    local keys = dict:get_keys(0)
    local services = core.table.new(0, #keys)
    local prefix = "default/"
    for i, key in ipairs(keys) do
        -- only return default registry nodes, strip prefix for BC
        if core.string.has_prefix(key, prefix) then
            local value = dict:get(key)
            if value then
                local nodes, err = core.json.decode(value)
                if nodes then
                    local bare_key = key:sub(#prefix + 1)
                    services[bare_key] = nodes
                else
                    log.error("failed to decode nodes for service: ", key, ", error: ", err)
                end
            end
        end

        if i % 100 == 0 then
            ngx.sleep(0)
        end
    end
    return services
end


-- ─── Initialization ───────────────────────────────────────────────────

function _M.init_worker()
    local consul_conf = local_conf.discovery and local_conf.discovery.consul
    if not consul_conf then
        return
    end

    local dict = ngx.shared[dict_name]
    if not dict then
        error('lua_shared_dict "' .. dict_name .. '" not configured')
    end
    consul_dict = dict

    log.notice("consul_conf: ", json_delay_encode(consul_conf, true))

    -- shallow copy to avoid mutating cached config
    local conf = {}
    for k, v in pairs(consul_conf) do
        conf[k] = v
    end
    conf.id = "default"

    -- create default registry on all workers so nodes()/control_api() work
    local reg = _M.create_registry(conf)

    -- only the privileged agent runs timers / writes to shared dict
    if process.type() ~= "privileged agent" then
        return
    end

    -- flush stale data for the default registry that may persist across reloads
    local prefix = "default/"
    local all_keys = dict:get_keys(0)
    for _, key in ipairs(all_keys) do
        if core.string.has_prefix(key, prefix) then
            dict:delete(key)
        end
    end

    _M.start_registry(reg)
end


function _M.dump_data()
    return {config = local_conf.discovery and local_conf.discovery.consul,
            services = _M.all_nodes()}
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris = {"/show_dump_file"},
            handler = function()
                local default_reg = registries["default"]
                return show_dump_file(default_reg)
            end,
        }
    }
end


return _M
