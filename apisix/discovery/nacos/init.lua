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
local http               = require('resty.http')
local core               = require('apisix.core')
local ipairs             = ipairs
local type               = type
local math               = math
local math_random        = math.random
local ngx                = ngx
local ngx_re             = require('ngx.re')
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string             = string
local string_sub         = string.sub
local str_byte           = string.byte
local str_find           = core.string.find
local log                = core.log

local default_weight
local applications
local auth_path = 'auth/login'
local instance_list_path = 'ns/instance/list?healthyOnly=true&serviceName='
local default_namespace_id = "public"
local default_group_name = "DEFAULT_GROUP"

local events
local events_list


local _M = {}

local function discovery_nacos_callback(data, event, source, pid)
    applications = data
    log.notice("update local variable application, event is: ", event,
               "source: ", source, "server pid:", pid,
               ", application: ", core.json.encode(applications, true))
end

local function request(request_uri, path, body, method, basic_auth)
    local url = request_uri .. path
    log.info('request url:', url)
    local headers = {}
    headers['Accept'] = 'application/json'

    if basic_auth then
        headers['Authorization'] = basic_auth
    end

    if body and 'table' == type(body) then
        local err
        body, err = core.json.encode(body)
        if not body then
            return nil, 'invalid body : ' .. err
        end
        headers['Content-Type'] = 'application/json'
    end

    local httpc = http.new()
    local timeout = local_conf.discovery.nacos.timeout
    local connect_timeout = timeout.connect
    local send_timeout = timeout.send
    local read_timeout = timeout.read
    log.info('connect_timeout:', connect_timeout, ', send_timeout:', send_timeout,
             ', read_timeout:', read_timeout)
    httpc:set_timeouts(connect_timeout, send_timeout, read_timeout)
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = headers,
        body = body,
        ssl_verify = true,
    })
    if not res then
        return nil, err
    end

    if not res.body or res.status ~= 200 then
        return nil, 'status = ' .. res.status
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        return nil, err
    end
    return data
end


local function get_url(request_uri, path)
    return request(request_uri, path, nil, 'GET', nil)
end


local function post_url(request_uri, path, body)
    return request(request_uri, path, body, 'POST', nil)
end


local function get_token_param(base_uri, username, password)
    if not username or not password then
        return ''
    end

    local args = { username = username, password = password}
    local data, err = post_url(base_uri, auth_path .. '?' .. ngx.encode_args(args), nil)
    if err then
        log.error('nacos login fail:', username, ' ', password, ' desc:', err)
        return nil, err
    end
    return '&accessToken=' .. data.accessToken
end

local function get_namespace_param(namespace_id)
    local param = ''
    if namespace_id then
        local args = {namespaceId = namespace_id}
        param = '&' .. ngx.encode_args(args)
    end
    return param
end

local function get_group_name_param(group_name)
    local param = ''
    if group_name then
        local args = {groupName = group_name}
        param = '&' .. ngx.encode_args(args)
    end
    return param
end

local function get_base_uri()
    local host = local_conf.discovery.nacos.host
    -- TODO Add health check to get healthy nodes.
    local url = host[math_random(#host)]
    local auth_idx = core.string.rfind_char(url, '@')
    local username, password
    if auth_idx then
        local protocol_idx = str_find(url, '://')
        local protocol = string_sub(url, 1, protocol_idx + 2)
        local user_and_password = string_sub(url, protocol_idx + 3, auth_idx - 1)
        local arr = ngx_re.split(user_and_password, ':')
        if #arr == 2 then
            username = arr[1]
            password = arr[2]
        end
        local other = string_sub(url, auth_idx + 1)
        url = protocol .. other
    end

    if local_conf.discovery.nacos.prefix then
        url = url .. local_conf.discovery.nacos.prefix
    end

    if str_byte(url, #url) ~= str_byte('/') then
        url = url .. '/'
    end

    return url, username, password
end


local function de_duplication(services, namespace_id, group_name, service_name, scheme)
    for _, service in ipairs(services) do
        if service.namespace_id == namespace_id and service.group_name == group_name
                and service.service_name == service_name and service.scheme == scheme then
            return true
        end
    end
    return false
end


local function iter_and_add_service(services, values)
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

        local namespace_id = (up.discovery_args and up.discovery_args.namespace_id)
                             or default_namespace_id

        local group_name = (up.discovery_args and up.discovery_args.group_name)
                           or default_group_name

        local dup = de_duplication(services, namespace_id, group_name,
                up.service_name, up.scheme)
        if dup then
            goto CONTINUE
        end

        if up.discovery_type == 'nacos' then
            core.table.insert(services, {
                service_name = up.service_name,
                namespace_id = namespace_id,
                group_name = group_name,
                scheme = up.scheme,
            })
        end
        ::CONTINUE::
    end
end


local function get_nacos_services()
    local services = {}

    -- here we use lazy load to work around circle dependency
    local get_upstreams = require('apisix.upstream').upstreams
    local get_routes = require('apisix.router').http_routes
    local get_stream_routes = require('apisix.router').stream_routes
    local get_services = require('apisix.http.service').services
    local values = get_upstreams()
    iter_and_add_service(services, values)
    values = get_routes()
    iter_and_add_service(services, values)
    values = get_services()
    iter_and_add_service(services, values)
    values = get_stream_routes()
    iter_and_add_service(services, values)
    return services
end

local function is_grpc(scheme)
    if scheme == 'grpc' or scheme == 'grpcs' then
        return true
    end

    return false
end

local function fetch_full_registry(premature)
    if premature then
        return
    end

    local up_apps = {}
    local base_uri, username, password = get_base_uri()
    local token_param, err = get_token_param(base_uri, username, password)
    if err then
        log.error('get_token_param error:', err)
        if not applications then
            applications = up_apps
        end
        return
    end

    local infos = get_nacos_services()
    if #infos == 0 then
        applications = up_apps
        return
    end

    for _, service_info in ipairs(infos) do
        local data, err
        local namespace_id = service_info.namespace_id
        local group_name = service_info.group_name
        local scheme = service_info.scheme or ''
        local namespace_param = get_namespace_param(service_info.namespace_id)
        local group_name_param = get_group_name_param(service_info.group_name)
        local query_path = instance_list_path .. service_info.service_name
                           .. token_param .. namespace_param .. group_name_param
        data, err = get_url(base_uri, query_path)
        if err then
            log.error('get_url:', query_path, ' err:', err)
            goto CONTINUE
        end

        if not up_apps[namespace_id] then
            up_apps[namespace_id] = {}
        end

        if not up_apps[namespace_id][group_name] then
            up_apps[namespace_id][group_name] = {}
        end

        for _, host in ipairs(data.hosts) do
            local nodes = up_apps[namespace_id]
                [group_name][service_info.service_name]
            if not nodes then
                nodes = {}
                up_apps[namespace_id]
                    [group_name][service_info.service_name] = nodes
            end

            local node = {
                host = host.ip,
                port = host.port,
                weight = host.weight or default_weight,
            }

            -- docs: https://github.com/yidongnan/grpc-spring-boot-starter/pull/496
            if is_grpc(scheme) and host.metadata and host.metadata.gRPC_port then
                node.port = host.metadata.gRPC_port
            end

            core.table.insert(nodes, node)
        end

        ::CONTINUE::
    end
    local new_apps_md5sum = ngx.md5(core.json.encode(up_apps))
    local old_apps_md5sum = ngx.md5(core.json.encode(applications))
    if new_apps_md5sum == old_apps_md5sum then
        return
    end
    applications = up_apps
    local ok, err = events.post(events_list._source, events_list.updating,
                                applications)
    if not ok then
        log.error("post_event failure with ", events_list._source,
                  ", update application error: ", err)
    end
end


function _M.nodes(service_name, discovery_args)
    local namespace_id = discovery_args and
            discovery_args.namespace_id or default_namespace_id
    local group_name = discovery_args
            and discovery_args.group_name or default_group_name

    local logged = false
    -- maximum waiting time: 5 seconds
    local waiting_time = 5
    local step = 0.1
    while not applications and waiting_time > 0 do
        if not logged then
            log.warn('wait init')
            logged = true
        end
        ngx.sleep(step)
        waiting_time = waiting_time - step
    end

    if not applications[namespace_id] or not applications[namespace_id][group_name] then
        return nil
    end
    return applications[namespace_id][group_name][service_name]
end


function _M.init_worker()
    events = require("resty.worker.events")
    events_list = events.event_list("discovery_nacos_update_application",
                                    "updating")

    if 0 ~= ngx.worker.id() then
        events.register(discovery_nacos_callback, events_list._source,
                        events_list.updating)
        return
    end

    default_weight = local_conf.discovery.nacos.weight
    log.info('default_weight:', default_weight)
    local fetch_interval = local_conf.discovery.nacos.fetch_interval
    log.info('fetch_interval:', fetch_interval)
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


function _M.dump_data()
    return {config = local_conf.discovery.nacos, services = applications or {}}
end


return _M
