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

--- Reusable HTTP client primitives for Consul service discovery.
--- Extracted from init.lua so that both static-config mode and
--- dynamic-config mode can share the same core logic.

local require            = require
local core               = require("apisix.core")
local core_sleep         = require("apisix.core.utils").sleep
local resty_consul       = require('resty.consul')
local http               = require('resty.http')
local ipairs             = ipairs
local pairs              = pairs
local unpack             = unpack
local tonumber           = tonumber
local type               = type
local next               = next
local tostring           = tostring
local ngx                = ngx
local math_random        = math.random
local log                = core.log
local json_delay_encode  = core.json.delay_encode
local pcall              = pcall
local null               = ngx.null

local _M = {}

-- Registry id for the implicit single-instance namespace. When service_name
-- is written without a "/" prefix, it is treated as belonging to this registry.
local DEFAULT_REGISTRY_ID = "default"
_M.DEFAULT_REGISTRY_ID = DEFAULT_REGISTRY_ID

local default_random_range = 5
local default_catalog_error_index = -1
local default_health_error_index = -2
local watch_type_catalog = 1
local watch_type_health = 2
local max_retry_time = 256


-- ─── helpers ──────────────────────────────────────────────────────────

function _M.get_retry_delay(retry_delay)
    if not retry_delay or retry_delay >= max_retry_time then
        retry_delay = 1
    else
        retry_delay = retry_delay * 4
    end

    return retry_delay
end


local function is_not_empty(value)
    if value == nil or value == null
            or (type(value) == "table" and not next(value))
            or (type(value) == "string" and value == "")
    then
        return false
    end

    return true
end


-- ─── sort comparators ─────────────────────────────────────────────────

local function combine_sort_nodes_cmp(left, right)
    if left.host ~= right.host then
        return left.host < right.host
    end

    return left.port < right.port
end


local function port_sort_nodes_cmp(left, right)
    return left.port < right.port
end


local function host_sort_nodes_cmp(left, right)
    return left.host < right.host
end


function _M.sort_nodes(nodes, sort_type)
    if not nodes or not sort_type or sort_type == "origin" then
        return
    end

    if sort_type == "port_sort" then
        core.table.sort(nodes, port_sort_nodes_cmp)
    elseif sort_type == "host_sort" then
        core.table.sort(nodes, host_sort_nodes_cmp)
    elseif sort_type == "combine_sort" then
        core.table.sort(nodes, combine_sort_nodes_cmp)
    end
end


-- ─── resty.consul options ─────────────────────────────────────────────

local function get_opts(consul_server, is_catalog)
    local opts = {
        host = consul_server.host,
        port = consul_server.port,
        connect_timeout = consul_server.connect_timeout,
        read_timeout = consul_server.read_timeout,
        default_args = {
            token = consul_server.token,
        }
    }
    if not consul_server.keepalive then
        return opts
    end

    opts.default_args.wait = consul_server.wait_timeout

    if is_catalog then
        opts.default_args.index = consul_server.catalog_index
    else
        opts.default_args.index = consul_server.health_index
    end

    return opts
end


-- ─── blocking query watchers ──────────────────────────────────────────

function _M.watch_catalog(consul_server)
    local client = resty_consul:new(get_opts(consul_server, true))

    ::RETRY::
    local watch_result, watch_err = client:get(consul_server.consul_watch_catalog_url)
    local watch_error_info = (watch_err ~= nil and watch_err)
                             or ((watch_result ~= nil and watch_result.status ~= 200)
                             and watch_result.status)
    if watch_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_catalog_url,
            ", got watch result: ", json_delay_encode(watch_result),
            ", with error: ", watch_error_info)

        return watch_type_catalog, default_catalog_error_index
    end

    if consul_server.catalog_index > 0
            and consul_server.catalog_index == tonumber(watch_result.headers['X-Consul-Index']) then
        local random_delay = math_random(default_random_range)
        log.info("watch catalog has no change, re-watch consul after ", random_delay, " seconds")
        core_sleep(random_delay)
        goto RETRY
    end

    return watch_type_catalog, watch_result.headers['X-Consul-Index']
end


function _M.watch_health(consul_server)
    local client = resty_consul:new(get_opts(consul_server, false))

    ::RETRY::
    local watch_result, watch_err = client:get(consul_server.consul_watch_health_url)
    local watch_error_info = (watch_err ~= nil and watch_err)
            or ((watch_result ~= nil and watch_result.status ~= 200)
            and watch_result.status)
    if watch_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_health_url,
            ", got watch result: ", json_delay_encode(watch_result),
            ", with error: ", watch_error_info)

        return watch_type_health, default_health_error_index
    end

    if consul_server.health_index > 0
            and consul_server.health_index == tonumber(watch_result.headers['X-Consul-Index']) then
        local random_delay = math_random(default_random_range)
        log.info("watch health has no change, re-watch consul after ", random_delay, " seconds")
        core_sleep(random_delay)
        goto RETRY
    end

    return watch_type_health, watch_result.headers['X-Consul-Index']
end


function _M.watch_result_is_valid(watch_type, index, catalog_index, health_index)
    if index <= 0 then
        return false
    end

    if watch_type == watch_type_catalog then
        if index == catalog_index then
            return false
        end
    else
        if index == health_index then
            return false
        end
    end

    return true
end


function _M.update_index(consul_server, catalog_index, health_index)
    local c_index = 0
    local h_index = 0
    if catalog_index ~= nil then
        c_index = tonumber(catalog_index)
    end

    if health_index ~= nil then
        h_index = tonumber(health_index)
    end

    if c_index > 0 then
        consul_server.catalog_index = c_index
    end

    if h_index > 0 then
        consul_server.health_index = h_index
    end
end


-- ─── URL parsing ──────────────────────────────────────────────────────

function _M.format_consul_params(consul_conf)
    local servers = consul_conf.servers
    local consul_server_list = core.table.new(0, #servers)

    for _, v in pairs(servers) do
        local scheme, host, port, path = unpack(http.parse_uri(nil, v))
        if scheme ~= "http" then
            return nil, "only support consul http schema address, eg: http://address:port"
        elseif path ~= "/" or core.string.has_suffix(v, '/') then
            return nil, "invalid consul server address, the valid format: http://address:port"
        end
        core.table.insert(consul_server_list, {
            host = host,
            port = port,
            token = consul_conf.token,
            connect_timeout = consul_conf.timeout.connect,
            read_timeout = consul_conf.timeout.read,
            wait_timeout = consul_conf.timeout.wait,
            consul_watch_catalog_url = "/catalog/services",
            consul_sub_url = "/health/service",
            consul_watch_health_url = "/health/state/any",
            consul_server_url = v .. "/v1",
            weight = consul_conf.weight,
            keepalive = consul_conf.keepalive,
            health_index = 0,
            catalog_index = 0,
            fetch_interval = consul_conf.fetch_interval,
        })
    end
    return consul_server_list, nil
end


-- ─── service fetching ─────────────────────────────────────────────────

--- Fetch all services from a single consul server.
--- Returns: up_services, err, catalog_index, health_index
---   up_services: table of key -> nodes (nil on failure)
---   err: error string (nil on success)
---   catalog_index: latest catalog index from consul
---   health_index: latest health index from consul
---
--- options:
---   default_weight     (number)    default node weight
---   sort_type          (string)    "origin"/"host_sort"/"port_sort"/"combine_sort"
---   skip_service_map   (table)     set of service names to skip
---   preserve_metadata  (bool)      include Service.Meta in returned nodes
---   key_builder        (function)  key_builder(service_name) -> string for the result key
function _M.fetch_services_from_server(consul_server, options)
    options = options or {}
    local default_weight = options.default_weight or 1
    local sort_type = options.sort_type
    local skip_service_map = options.skip_service_map or {}
    local preserve_metadata = options.preserve_metadata or false
    local key_builder = options.key_builder

    local consul_client = resty_consul:new({
        host = consul_server.host,
        port = consul_server.port,
        connect_timeout = consul_server.connect_timeout,
        read_timeout = consul_server.read_timeout,
        default_args = {
            token = consul_server.token
        }
    })

    -- fetch catalog
    local catalog_success, catalog_res, catalog_err = pcall(function()
        return consul_client:get(consul_server.consul_watch_catalog_url)
    end)
    if not catalog_success then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_catalog_url,
            ", got catalog result: ", json_delay_encode(catalog_res))
        return nil, "catalog fetch failed"
    end
    local catalog_error_info = (catalog_err ~= nil and catalog_err)
            or ((catalog_res ~= nil and catalog_res.status ~= 200)
            and catalog_res.status)
    if catalog_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_catalog_url,
            ", got catalog result: ", json_delay_encode(catalog_res),
            ", with error: ", catalog_error_info)
        return nil, "catalog error: " .. tostring(catalog_error_info)
    end

    -- fetch health index
    local success, health_res, health_err = pcall(function()
        return consul_client:get(consul_server.consul_watch_health_url)
    end)
    if not success then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_health_url,
            ", got health result: ", json_delay_encode(health_res))
        return nil, "health fetch failed"
    end
    local health_error_info = (health_err ~= nil and health_err)
            or ((health_res ~= nil and health_res.status ~= 200)
            and health_res.status)
    if health_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_health_url,
            ", got health result: ", json_delay_encode(health_res),
            ", with error: ", health_error_info)
        return nil, "health error: " .. tostring(health_error_info)
    end

    log.info("connect consul: ", consul_server.consul_server_url,
        ", catalog_result status: ", catalog_res.status,
        ", catalog_result.headers.index: ", catalog_res.headers['X-Consul-Index'],
        ", consul_server.index: ", consul_server.index,
        ", consul_server: ", json_delay_encode(consul_server))

    -- check if index changed
    if consul_server.catalog_index == tonumber(catalog_res.headers['X-Consul-Index'])
            and consul_server.health_index == tonumber(health_res.headers['X-Consul-Index']) then
        return {}, nil, catalog_res.headers['X-Consul-Index'],
                        health_res.headers['X-Consul-Index']
    end

    -- build service nodes
    local up_services = core.table.new(0, #catalog_res.body)
    for service_name, _ in pairs(catalog_res.body) do
        if skip_service_map[service_name] then
            goto CONTINUE
        end

        local svc_url = consul_server.consul_sub_url .. "/" .. service_name
        local svc_success, result, get_err = pcall(function()
            return consul_client:get(svc_url, {passing = true})
        end)
        local error_info = (get_err ~= nil and get_err) or
                ((result ~= nil and result.status ~= 200) and result.status)
        if not svc_success or error_info then
            log.error("connect consul: ", consul_server.consul_server_url,
                ", by service url: ", svc_url, ", with error: ", error_info)
            goto CONTINUE
        end

        if is_not_empty(result.body) then
            local key = service_name
            if key_builder then
                key = key_builder(service_name)
            end

            local nodes = up_services[key]
            local nodes_uniq = {}
            for _, node in ipairs(result.body) do
                if not node.Service then
                    goto CONTINUE
                end

                local svc_address, svc_port = node.Service.Address, node.Service.Port
                if not svc_port or svc_port == 0 then
                    svc_port = 80
                end
                if not nodes then
                    nodes = core.table.new(1, 0)
                    up_services[key] = nodes
                end
                local service_id = svc_address .. ":" .. svc_port
                if not nodes_uniq[service_id] then
                    local n = {
                        host = svc_address,
                        port = tonumber(svc_port),
                        weight = default_weight,
                    }
                    if preserve_metadata and node.Service.Meta
                            and next(node.Service.Meta) then
                        n.metadata = node.Service.Meta
                    end
                    core.table.insert(nodes, n)
                    nodes_uniq[service_id] = true
                end
            end

            if nodes then
                _M.sort_nodes(nodes, sort_type)
            end
            up_services[key] = nodes
        end
        :: CONTINUE ::
    end

    return up_services, nil, catalog_res.headers['X-Consul-Index'],
                              health_res.headers['X-Consul-Index']
end


-- ─── service scanning ─────────────────────────────────────────────────

local function iter_and_add_service(services, values, id)
    if not values then
        return
    end

    for _, value in core.config_util.iterate_values(values) do
        local conf = value.value
        if not conf then
            goto CONTINUE
        end

        local up
        if conf.upstream then
            up = conf.upstream
        else
            up = conf
        end

        if up.discovery_type ~= 'consul' then
            goto CONTINUE
        end

        local svc_name = up.service_name
        local m = ngx.re.match(svc_name, "^(.*?)/(.*)$", "jo")
        if m then
            -- explicit "{registry_id}/{name}" — filter by prefix and strip
            if m[1] ~= id then
                goto CONTINUE
            end
            svc_name = m[2]
        else
            -- no prefix — implicit default namespace
            if id ~= DEFAULT_REGISTRY_ID then
                goto CONTINUE
            end
        end

        if not services[svc_name] then
            services[svc_name] = true
        end
        ::CONTINUE::
    end
end


--- Scan APISIX routes/services/upstreams for consul discovery references.
--- id: registry id to filter by. Service names written as "{id}/{name}" match
---     by strict prefix and are returned stripped. Service names without "/"
---     are treated as belonging to the implicit default registry and match
---     only when id == DEFAULT_REGISTRY_ID.
function _M.get_consul_services(id)
    local services = {}

    local get_upstreams = require('apisix.upstream').upstreams
    local get_routes = require('apisix.router').http_routes
    local get_stream_routes = require('apisix.router').stream_routes
    local get_services = require('apisix.http.service').services

    iter_and_add_service(services, get_upstreams(), id)
    iter_and_add_service(services, get_routes(), id)
    iter_and_add_service(services, get_services(), id)
    iter_and_add_service(services, get_stream_routes(), id)

    return services
end


return _M
