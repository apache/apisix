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

--- Reusable HTTP client primitives for Nacos service discovery.
--- Extracted from init.lua so that both static-config mode and
--- dynamic-config mode can share the same core logic.

local require         = require
local http            = require('resty.http')
local core            = require('apisix.core')
local ipairs          = ipairs
local pairs           = pairs
local type            = type
local ngx             = ngx
local ngx_re          = require('ngx.re')
local string          = string
local string_sub      = string.sub
local str_byte        = string.byte
local str_find        = core.string.find
local log             = core.log

local auth_path = 'auth/login'
local instance_list_path = 'ns/instance/list?healthyOnly=true&serviceName='
local default_namespace_id = "public"
local default_group_name = "DEFAULT_GROUP"


local _M = {}


-- ─── HTTP primitives ──────────────────────────────────────────────────

function _M.request(request_uri, path, body, method, basic_auth, timeout)
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
    timeout = timeout or {}
    local connect_timeout = timeout.connect or 2000
    local send_timeout = timeout.send or 5000
    local read_timeout = timeout.read or 5000
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
    local data, decode_err = core.json.decode(json_str)
    if not data then
        return nil, decode_err
    end
    return data
end


-- ─── authentication ───────────────────────────────────────────────────

function _M.get_token_param(base_uri, username, password, timeout)
    if not username or not password then
        return ''
    end

    local args = { username = username, password = password }
    local data, err = _M.request(base_uri, auth_path .. '?' .. ngx.encode_args(args),
                                 nil, 'POST', nil, timeout)
    if err then
        log.error('nacos login fail:', username, ' ', password, ' desc:', err)
        return nil, err
    end
    return '&accessToken=' .. data.accessToken
end


function _M.get_signed_param(group_name, service_name, access_key, secret_key)
    local param = ''
    if access_key and access_key ~= '' and secret_key and secret_key ~= '' then
        local str_to_sign = ngx.now() * 1000 .. '@@' .. group_name .. '@@' .. service_name
        local args = {
            ak = access_key,
            data = str_to_sign,
            signature = ngx.encode_base64(ngx.hmac_sha1(secret_key, str_to_sign))
        }
        param = '&' .. ngx.encode_args(args)
    end
    return param
end


-- ─── URL building ─────────────────────────────────────────────────────

function _M.build_base_uri(url, prefix)
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

    if prefix then
        url = url .. prefix
    end

    if str_byte(url, #url) ~= str_byte('/') then
        url = url .. '/'
    end

    return url, username, password
end


-- ─── query param helpers ──────────────────────────────────────────────

local function get_namespace_param(namespace_id)
    local param = ''
    if namespace_id then
        local args = { namespaceId = namespace_id }
        param = '&' .. ngx.encode_args(args)
    end
    return param
end


local function get_group_name_param(group_name)
    local param = ''
    if group_name then
        local args = { groupName = group_name }
        param = '&' .. ngx.encode_args(args)
    end
    return param
end


local function is_grpc(scheme)
    return scheme == 'grpc' or scheme == 'grpcs'
end


-- ─── instance fetching ────────────────────────────────────────────────

--- Fetch instances from a single nacos host for a list of services.
---
--- Returns: service_nodes (table of key → nodes), service_names (set), ok (bool)
---
--- options:
---   default_weight     (number)    default node weight
---   access_key         (string)    AK for HMAC-SHA1 signing (optional)
---   secret_key         (string)    SK for HMAC-SHA1 signing (optional)
---   timeout            (table)     { connect, send, read } in ms
---   preserve_metadata  (bool)      include instance.metadata in returned nodes
---   key_builder        (function)  key_builder(namespace_id, group_name, service_name)
---                                  returns the key to use for this service in the result.
---                                  default: namespace_id .. '.' .. group_name .. '.' .. service_name

function _M.fetch_from_host(base_uri, username, password, services, options)
    options = options or {}
    local dw = options.default_weight or 100
    local ak = options.access_key
    local sk = options.secret_key
    local timeout = options.timeout
    local preserve_metadata = options.preserve_metadata
    local key_builder = options.key_builder

    local token_param, err = _M.get_token_param(base_uri, username, password, timeout)
    if err then
        return nil, nil, err
    end

    local service_names = {}
    local nodes_cache = {}
    local had_success = false

    for _, service_info in ipairs(services) do
        local namespace_id = service_info.namespace_id
        local group_name = service_info.group_name
        local scheme = service_info.scheme or ''
        local namespace_param = get_namespace_param(namespace_id)
        local group_name_param = get_group_name_param(group_name)
        local signature_param = _M.get_signed_param(
            group_name, service_info.service_name, ak, sk)
        local query_path = instance_list_path .. service_info.service_name
                           .. token_param .. namespace_param .. group_name_param
                           .. signature_param
        local data, req_err = _M.request(base_uri, query_path, nil, 'GET', nil, timeout)
        if req_err then
            log.error('failed to fetch instances for service [', service_info.service_name,
                      '] from ', base_uri, ', error: ', req_err)
        else
            had_success = true

            local key
            if key_builder then
                key = key_builder(namespace_id, group_name, service_info.service_name)
            else
                key = namespace_id .. '.' .. group_name .. '.' .. service_info.service_name
            end
            service_names[key] = true

            local hosts = data.hosts
            if type(hosts) ~= 'table' then
                hosts = {}
            end

            local nodes = {}
            for _, host in ipairs(hosts) do
                local node = {
                    host = host.ip,
                    port = host.port,
                    weight = host.weight or dw,
                }
                if is_grpc(scheme) and host.metadata and host.metadata.gRPC_port then
                    node.port = host.metadata.gRPC_port
                end
                if preserve_metadata and host.metadata then
                    node.metadata = host.metadata
                end
                core.table.insert(nodes, node)
            end

            if #nodes > 0 then
                nodes_cache[key] = nodes
            end
        end
    end

    if not had_success then
        return nil, nil, 'all nacos services fetch failed'
    end

    return nodes_cache, service_names
end


-- ─── service scanning ─────────────────────────────────────────────────

local function de_duplication(services, namespace_id, group_name, service_name, scheme)
    for _, service in ipairs(services) do
        if service.namespace_id == namespace_id and service.group_name == group_name
                and service.service_name == service_name and service.scheme == scheme then
            return true
        end
    end
    return false
end


local function iter_and_add_service(services, values, filter)
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

        if up.discovery_type ~= 'nacos' then
            goto CONTINUE
        end

        if filter and not filter(up) then
            goto CONTINUE
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

        core.table.insert(services, {
            service_name = up.service_name,
            namespace_id = namespace_id,
            group_name = group_name,
            scheme = up.scheme,
        })
        ::CONTINUE::
    end
end


--- Scan APISIX routes/services/upstreams for nacos discovery references.
--- filter: optional function(upstream) → bool, called on each upstream config.
function _M.get_nacos_services(filter)
    local services = {}

    -- lazy load to work around circular dependency
    local get_upstreams = require('apisix.upstream').upstreams
    local get_routes = require('apisix.router').http_routes
    local get_stream_routes = require('apisix.router').stream_routes
    local get_services = require('apisix.http.service').services
    local values = get_upstreams()
    iter_and_add_service(services, values, filter)
    values = get_routes()
    iter_and_add_service(services, values, filter)
    values = get_services()
    iter_and_add_service(services, values, filter)
    values = get_stream_routes()
    iter_and_add_service(services, values, filter)
    return services
end


return _M
