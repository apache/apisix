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

local all_services = core.table.new(0, 5)
local default_service
local default_weight
local skip_service_map = core.table.new(0, 1)
local dump_params

local events
local events_list
local consul_services

local default_skip_services = {"consul"}

local _M = {
    version = 0.2,
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
    if dump_params.expire ~= 0  and (entity.last_update + dump_params.expire) < now_time then
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
    local succ, err =  util.write_file(dump_params.path, data)
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
    if not retry_delay then
        retry_delay = 1
    else
        retry_delay = retry_delay * 4
    end

    return retry_delay
end


function _M.connect(premature, consul_server, retry_delay)
    if premature then
        return
    end

    local consul_client = resty_consul:new({
        host = consul_server.host,
        port = consul_server.port,
        connect_timeout = consul_server.connect_timeout,
        read_timeout = consul_server.read_timeout,
        default_args = consul_server.default_args,
    })

    log.info("consul_server: ", json_delay_encode(consul_server, true))
    local watch_result, watch_err = consul_client:get(consul_server.consul_watch_sub_url)
    local watch_error_info = (watch_err ~= nil and watch_err)
            or ((watch_result ~= nil and watch_result.status ~= 200)
            and watch_result.status)
    if watch_error_info then
        log.error("connect consul: ", consul_server.consul_server_url,
            " by sub url: ", consul_server.consul_watch_sub_url,
            ", got watch result: ", json_delay_encode(watch_result, true),
            ", with error: ", watch_error_info)

        retry_delay = get_retry_delay(retry_delay)
        log.warn("retry connecting consul after ", retry_delay, " seconds")
        core_sleep(retry_delay)

        goto ERR
    end

    log.info("connect consul: ", consul_server.consul_server_url,
        ", watch_result status: ", watch_result.status,
        ", watch_result.headers.index: ", watch_result.headers['X-Consul-Index'],
        ", consul_server.index: ", consul_server.index,
        ", consul_server: ", json_delay_encode(consul_server, true))

    -- if current index different last index then update service
    if consul_server.index ~= watch_result.headers['X-Consul-Index'] then
        local up_services = core.table.new(0, #watch_result.body)
        local consul_client_svc = resty_consul:new({
            host = consul_server.host,
            port = consul_server.port,
            connect_timeout = consul_server.connect_timeout,
            read_timeout = consul_server.read_timeout,
        })
        for service_name, _ in pairs(watch_result.body) do
            -- check if the service_name is 'skip service'
            if skip_service_map[service_name] then
                goto CONTINUE
            end
            -- get node from service
            local svc_url = consul_server.consul_sub_url .. "/" .. service_name
            local result, err = consul_client_svc:get(svc_url)
            local error_info = (err ~= nil and err) or
                    ((result ~= nil and result.status ~= 200) and result.status)
            if error_info then
                log.error("connect consul: ", consul_server.consul_server_url,
                    ", by service url: ", svc_url, ", with error: ", error_info)
                goto CONTINUE
            end

            -- decode body, decode json, update service, error handling
            if result.body then
                log.notice("service url: ", svc_url,
                    ", header: ", json_delay_encode(result.headers, true),
                    ", body: ", json_delay_encode(result.body, true))
                -- add services to table
                local nodes = up_services[service_name]
                for  _, node in ipairs(result.body) do
                    local svc_address, svc_port = node.ServiceAddress, node.ServicePort
                    if not svc_address then
                        svc_address = node.Address
                    end
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
        local ok, post_err = events.post(events_list._source, events_list.updating, all_services)
        if not ok then
            log.error("post_event failure with ", events_list._source,
                ", update all services error: ", post_err)
        end

        if dump_params then
            ngx_timer_at(0, write_dump_services)
        end

        consul_server.index = watch_result.headers['X-Consul-Index']
        -- only long connect type use index
        if consul_server.keepalive then
            consul_server.default_args.index = watch_result.headers['X-Consul-Index']
        end
    end

    :: ERR ::
    local keepalive = consul_server.keepalive
    if keepalive then
        local ok, err = ngx_timer_at(0, _M.connect, consul_server, retry_delay)
        if not ok then
            log.error("create ngx_timer_at got error: ", err)
            return
        end
    end
end


local function format_consul_params(consul_conf)
    local consul_server_list = core.table.new(0, #consul_conf.servers)
    local args

    if consul_conf.keepalive == false then
        args = {}
    elseif consul_conf.keepalive then
        args = {
            wait = consul_conf.timeout.wait, --blocked wait!=0; unblocked by wait=0
            index = 0,
        }
    end

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
            connect_timeout = consul_conf.timeout.connect,
            read_timeout = consul_conf.timeout.read,
            consul_sub_url = "/catalog/service",
            consul_watch_sub_url = "/catalog/services",
            consul_server_url = v .. "/v1",
            weight = consul_conf.weight,
            keepalive = consul_conf.keepalive,
            default_args = args,
            index = 0,
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

    events = require("resty.worker.events")
    events_list = events.event_list(
            "discovery_consul_update_all_services",
            "updating"
    )

    if 0 ~= ngx_worker_id() then
        events.register(discovery_consul_callback, events_list._source, events_list.updating)
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
