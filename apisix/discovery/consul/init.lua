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
local resty_consul       = require('resty.consul')
local http               = require('resty.http')
local util               = require("apisix.cli.util")
local ipairs             = ipairs
local error              = error
local ngx                = ngx
local unpack             = unpack
local tonumber           = tonumber
local pairs              = pairs
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local log                = core.log
local json_delay_encode  = core.json.delay_encode
local ngx_worker_id      = ngx.worker.id
local exiting            = ngx.worker.exiting
local thread_spawn       = ngx.thread.spawn
local thread_wait        = ngx.thread.wait
local thread_kill        = ngx.thread.kill
local math_random        = math.random
local pcall              = pcall
local null               = ngx.null
local type               = type
local next               = next

local all_services = core.table.new(0, 5)
local default_service
local default_weight
local skip_service_map = core.table.new(0, 1)
local dump_params

local events
local events_list
local consul_services

local default_skip_services = {"consul"}
local default_random_range = 5
local default_catalog_error_index = -1
local default_health_error_index = -2
local watch_type_catalog = 1
local watch_type_health = 2
local max_retry_time = 256

local _M = {
    version = 0.3,
}


local function discovery_consul_callback(data, event, source, pid)
    all_services = data
    log.notice("update local variable all_services, event is: ", event,
        "source: ", source, "server pid:", pid,
        ", all services: ", json_delay_encode(all_services, true))
end


function _M.all_nodes()
    return all_services
end


function _M.nodes(service_name)
    if not all_services then
        log.error("all_services is nil, failed to fetch nodes for : ", service_name)
        return
    end

    local resp_list = all_services[service_name]

    if not resp_list then
        log.error("fetch nodes failed by ", service_name, ", return default service")
        return default_service and {default_service}
    end

    log.info("process id: ", ngx_worker_id(), ", all_services[", service_name, "] = ",
        json_delay_encode(resp_list, true))

    return resp_list
end


local function update_all_services(consul_server_url, up_services)
    -- clean old unused data
    local old_services = consul_services[consul_server_url] or {}
    for k, _ in pairs(old_services) do
        all_services[k] = nil
    end
    core.table.clear(old_services)

    for k, v in pairs(up_services) do
        all_services[k] = v
    end
    consul_services[consul_server_url] = up_services

    log.info("update all services: ", json_delay_encode(all_services, true))
end


local function read_dump_services()
    local data, err = util.read_file(dump_params.path)
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
        dump_params.expire, ", now_time: ", now_time)
    if dump_params.expire ~= 0 and (entity.last_update + dump_params.expire) < now_time then
        log.warn("dump file: ", dump_params.path, " had expired, ignored it")
        return
    end

    all_services = entity.services
    log.info("load dump file into memory success")
end


local function write_dump_services()
    local entity = {
        services = all_services,
        last_update = ngx.time(),
        expire = dump_params.expire, -- later need handle it
    }
    local data = core.json.encode(entity)
    local succ, err = util.write_file(dump_params.path, data)
    if not succ then
        log.error("write dump into file got error: ", err)
    end
end


local function show_dump_file()
    if not dump_params then
        return 503, "dump params is nil"
    end

    local data, err = util.read_file(dump_params.path)
    if not data then
        return 503, err
    end

    return 200, data
end


local function get_retry_delay(retry_delay)
    if not retry_delay or retry_delay >= max_retry_time then
        retry_delay = 1
    else
        retry_delay = retry_delay * 4
    end

    return retry_delay
end


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

    opts.default_args.wait = consul_server.wait_timeout --blocked wait!=0; unblocked by wait=0

    if is_catalog then
        opts.default_args.index = consul_server.catalog_index
    else
        opts.default_args.index = consul_server.health_index
    end

    return opts
end


local function watch_catalog(consul_server)
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


local function watch_health(consul_server)
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


local function check_keepalive(consul_server, retry_delay)
    if consul_server.keepalive and not exiting() then
        local ok, err = ngx_timer_at(0, _M.connect, consul_server, retry_delay)
        if not ok then
            log.error("create ngx_timer_at got error: ", err)
            return
        end
    end
end


local function update_index(consul_server, catalog_index, health_index)
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


local function is_not_empty(value)
    if value == nil or value == null
            or (type(value) == "table" and not next(value))
            or (type(value) == "string" and value == "")
    then
        return false
    end

    return true
end


local function watch_result_is_valid(watch_type, index, catalog_index, health_index)
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


function _M.connect(premature, consul_server, retry_delay)
    if premature then
        return
    end

    local catalog_thread, spawn_catalog_err = thread_spawn(watch_catalog, consul_server)
    if not catalog_thread then
        local random_delay = math_random(default_random_range)
        log.error("failed to spawn thread watch catalog: ", spawn_catalog_err,
            ", retry connecting consul after ", random_delay, " seconds")
        core_sleep(random_delay)

        check_keepalive(consul_server, retry_delay)
        return
    end

    local health_thread, err = thread_spawn(watch_health, consul_server)
    if not health_thread then
        thread_kill(catalog_thread)
        local random_delay = math_random(default_random_range)
        log.error("failed to spawn thread watch health: ", err, ", retry connecting consul after ",
            random_delay, " seconds")
        core_sleep(random_delay)

        check_keepalive(consul_server, retry_delay)
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

        check_keepalive(consul_server, retry_delay)
        return
    end

    -- double check index has changed
    if not watch_result_is_valid(tonumber(watch_type),
            tonumber(index), consul_server.catalog_index, consul_server.health_index) then
        retry_delay = get_retry_delay(retry_delay)
        log.warn("get all svcs got err, retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        check_keepalive(consul_server, retry_delay)
        return
    end

    local consul_client = resty_consul:new({
        host = consul_server.host,
        port = consul_server.port,
        connect_timeout = consul_server.connect_timeout,
        read_timeout = consul_server.read_timeout,
        default_args = {
            token = consul_server.token
        }
    })
    local catalog_success, catalog_res, catalog_err = pcall(function()
        return consul_client:get(consul_server.consul_watch_catalog_url)
    end)
    if not catalog_success then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_catalog_url,
            ", got catalog result: ", json_delay_encode(catalog_res))
        check_keepalive(consul_server, retry_delay)
        return
    end
    local catalog_error_info = (catalog_err ~= nil and catalog_err)
            or ((catalog_res ~= nil and catalog_res.status ~= 200)
            and catalog_res.status)
    if catalog_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_catalog_url,
            ", got catalog result: ", json_delay_encode(catalog_res),
            ", with error: ", catalog_error_info)

        retry_delay = get_retry_delay(retry_delay)
        log.warn("get all svcs got err, retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        check_keepalive(consul_server, retry_delay)
        return
    end

    -- get health index
    local success, health_res, health_err = pcall(function()
        return consul_client:get(consul_server.consul_watch_health_url)
    end)
    if not success then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_health_url,
            ", got health result: ", json_delay_encode(health_res))
        check_keepalive(consul_server, retry_delay)
        return
    end
    local health_error_info = (health_err ~= nil and health_err)
            or ((health_res ~= nil and health_res.status ~= 200)
            and health_res.status)
    if health_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_health_url,
            ", got health result: ", json_delay_encode(health_res),
            ", with error: ", health_error_info)

        retry_delay = get_retry_delay(retry_delay)
        log.warn("get all svcs got err, retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        check_keepalive(consul_server, retry_delay)
        return
    end

    log.info("connect consul: ", consul_server.consul_server_url,
        ", catalog_result status: ", catalog_res.status,
        ", catalog_result.headers.index: ", catalog_res.headers['X-Consul-Index'],
        ", consul_server.index: ", consul_server.index,
        ", consul_server: ", json_delay_encode(consul_server))

    -- if the current index is different from the last index, then update the service
    if (consul_server.catalog_index ~= tonumber(catalog_res.headers['X-Consul-Index']))
            or (consul_server.health_index ~= tonumber(health_res.headers['X-Consul-Index'])) then
        local up_services = core.table.new(0, #catalog_res.body)
        for service_name, _ in pairs(catalog_res.body) do
            -- check if the service_name is 'skip service'
            if skip_service_map[service_name] then
                goto CONTINUE
            end

            -- get node from service
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

            -- decode body, decode json, update service, error handling
            -- check result body is not nil and not empty
            if is_not_empty(result.body) then
                -- add services to table
                local nodes = up_services[service_name]
                for _, node in ipairs(result.body) do
                    if not node.Service then
                        goto CONTINUE
                    end

                    local svc_address, svc_port = node.Service.Address, node.Service.Port
                    -- if nodes is nil, new nodes table and set to up_services
                    if not nodes then
                        nodes = core.table.new(1, 0)
                        up_services[service_name] = nodes
                    end
                    -- add node to nodes table
                    core.table.insert(nodes, {
                        host = svc_address,
                        port = tonumber(svc_port),
                        weight = default_weight,
                    })
                end
                up_services[service_name] = nodes
            end
            :: CONTINUE ::
        end

        update_all_services(consul_server.consul_server_url, up_services)

        --update events
        local post_ok, post_err = events:post(events_list._source,
                events_list.updating, all_services)
        if not post_ok then
            log.error("post_event failure with ", events_list._source,
                ", update all services error: ", post_err)
        end

        if dump_params then
            ngx_timer_at(0, write_dump_services)
        end

        update_index(consul_server,
                catalog_res.headers['X-Consul-Index'],
                health_res.headers['X-Consul-Index'])
    end

    check_keepalive(consul_server, retry_delay)
end


local function format_consul_params(consul_conf)
    local consul_server_list = core.table.new(0, #consul_conf.servers)

    for _, v in pairs(consul_conf.servers) do
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
            fetch_interval = consul_conf.fetch_interval -- fetch interval to next connect consul
        })
    end
    return consul_server_list, nil
end


function _M.init_worker()
    local consul_conf = local_conf.discovery.consul

    if consul_conf.dump then
        local dump = consul_conf.dump
        dump_params = dump

        if dump.load_on_init then
            read_dump_services()
        end
    end

    events = require("apisix.event")
    events_list = events:event_list(
            "discovery_consul_update_all_services",
            "updating"
    )

    if 0 ~= ngx_worker_id() then
        events:register(discovery_consul_callback, events_list._source, events_list.updating)
        return
    end

    log.notice("consul_conf: ", json_delay_encode(consul_conf, true))
    default_weight = consul_conf.weight
    -- set default service, used when the server node cannot be found
    if consul_conf.default_service then
        default_service = consul_conf.default_service
        default_service.weight = default_weight
    end
    if consul_conf.skip_services then
        skip_service_map = core.table.new(0, #consul_conf.skip_services)
        for _, v in ipairs(consul_conf.skip_services) do
            skip_service_map[v] = true
        end
    end
    -- set up default skip service
    for _, v in ipairs(default_skip_services) do
        skip_service_map[v] = true
    end

    local consul_servers_list, err = format_consul_params(consul_conf)
    if err then
        error("format consul config got error: " .. err)
    end
    log.info("consul_server_list: ", json_delay_encode(consul_servers_list, true))

    consul_services = core.table.new(0, 1)
    -- success or failure
    for _, server in ipairs(consul_servers_list) do
        local ok, err = ngx_timer_at(0, _M.connect, server)
        if not ok then
            error("create consul got error: " .. err)
        end

        if server.keepalive == false then
            ngx_timer_every(server.fetch_interval, _M.connect, server)
        end
    end
end


function _M.dump_data()
    return {config = local_conf.discovery.consul, services = all_services }
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris = {"/show_dump_file"},
            handler = show_dump_file,
        }
    }
end


return _M
