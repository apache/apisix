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

local local_conf         = require("apisix.core.config_local").local_conf()
local http               = require("resty.http")
local core               = require("apisix.core")
local ipairs             = ipairs
local tostring           = tostring
local type               = type
local math_random        = math.random
local error              = error
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string             = string
local table              = table
local string_sub         = string.sub
local str_byte           = string.byte
local str_find           = core.string.find
local log                = core.log

local default_weight
local applications
local auth_path
local service_list_path
local instance_list_path

local schema = {
    type = "object",
    properties = {
        host = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
            },
        },
        fetch_interval = {type = "integer", minimum = 1, default = 30},
        prefix = {type = "string", default = "/nacos/v1/"},
        auth_path = {type = "string", default = "auth/login"},
        service_list_path = {type = "string", default = "ns/service/list?pageNo=1&pageSize=20"},
        instance_list_path = {type = "string", default = "ns/instance/list?serviceName="},
        weight = {type = "integer", minimum = 1, default = 100},
        timeout = {
            type = "object",
            properties = {
                connect = {type = "integer", minimum = 1, default = 2000},
                send = {type = "integer", minimum = 1, default = 2000},
                read = {type = "integer", minimum = 1, default = 5000},
            },
            default = {
                connect = 2000,
                send = 2000,
                read = 5000,
            }
        },
    },
    required = {"host"}
}


local _M = {
    version = 0.1,
}


local function str_split (inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end


local function service_info()
    local host = local_conf.discovery and
            local_conf.discovery.nacos and local_conf.discovery.nacos.host
    if not host then
        log.error("do not set nacos.host")
        return
    end

    local username, password
    -- TODO Add health check to get healthy nodes.
    local url = host[math_random(#host)]
    local auth_idx = str_find(url, "@")
    if auth_idx then
        local protocol_idx = str_find(url, "://")
        local protocol = string_sub(url, 1, protocol_idx + 2)
        local user_and_password = string_sub(url, protocol_idx + 3, auth_idx - 1)
        local arr = str_split(user_and_password,":")
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
    if str_byte(url, #url) ~= str_byte("/") then
        url = url .. "/"
    end

    return url, username, password
end


local function request(request_uri, path, body, method, basic_auth)
    log.info("nacos uri:", request_uri, ".")
    local url = request_uri .. path
    local headers = core.table.new(0, 0)
    headers['Connection'] = 'Keep-Alive'
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
        -- log.warn(method, url, body)
        headers['Content-Type'] = 'application/json'
    end

    local httpc = http.new()
    local timeout = local_conf.discovery.nacos.timeout
    local connect_timeout = timeout.connect
    local send_timeout = timeout.send
    local read_timeout = timeout.read
    log.info("connect_timeout:", connect_timeout, ", send_timeout:", send_timeout,
        ", read_timeout:", read_timeout, ".")
    httpc:set_timeouts(connect_timeout, send_timeout, read_timeout)
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = headers,
        body = body,
        ssl_verify = false,
    })
    if not res then
        return nil, err
    end

    if not res.body or res.status ~= 200 then
        return nil, "status = " .. res.status
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        return nil, err
    end
    return data
end


local function get_url(request_uri, path)
    return request(request_uri, path, nil, "GET", nil)
end


local function post_url(request_uri, path, body)
    return request(request_uri, path, body, "POST", nil)
end


local function fetch_full_registry(premature)
    if premature then
        return
    end

    local base_uri, username, password = service_info()
    if not base_uri then
        return
    end

    local token_param = ""
    if username and password then
        local data, err = post_url(base_uri, auth_path .. "?username=" .. username
                .. "&password=" .. password, nil)
        if err then
            log.error("nacos login fail:" .. username .. " " .. password .. " desc:" .. err)
            return
        end
        token_param = "&accessToken=" .. data.accessToken
    end

    local up_apps = core.table.new(0, 0)
    local data, err = get_url(base_uri, service_list_path .. token_param)
    if err then
        log.error("get_url:" .. service_list_path .. " err:" .. err)
        return
    end

    if tostring(data.count) == "0" then
        applications = up_apps
        return
    end

    for _, service_name in ipairs(data.doms) do
        data, err = get_url(base_uri, instance_list_path .. service_name .. token_param)
        if err then
            log.error("get_url:" .. instance_list_path .. " err:" .. err)
            return
        end

        for _, host in ipairs(data.hosts) do
            if tostring(host.valid) == 'true' and
                    tostring(host.healthy) == 'true' and
                    tostring(host.enabled) == 'true' then
                local nodes = up_apps[service_name]
                if not nodes then
                    nodes = core.table.new(0, 0)
                    up_apps[service_name] = nodes
                end
                core.table.insert(nodes, {
                    host = host.ip,
                    port = host.port,
                    weight = host.weight or default_weight,
                })
            end
        end
    end
    applications = up_apps
end


function _M.nodes(service_name)
    if not applications then
        log.error("failed to fetch nodes for : ", service_name)
        return
    end

    return applications[service_name]
end


function _M.init_worker()
    if not local_conf.discovery.nacos or
            not local_conf.discovery.nacos.host or #local_conf.discovery.nacos.host == 0 then
        error("do not set nacos.host")
        return
    end

    local ok, err = core.schema.check(schema, local_conf.discovery.nacos)
    if not ok then
        error("invalid nacos configuration: " .. err)
        return
    end
    default_weight = local_conf.discovery.nacos.weight
    log.info("default_weight:", default_weight, ".")
    local fetch_interval = local_conf.discovery.nacos.fetch_interval
    log.info("fetch_interval:", fetch_interval, ".")
    auth_path = local_conf.discovery.nacos.auth_path
    service_list_path = local_conf.discovery.nacos.service_list_path
    instance_list_path = local_conf.discovery.nacos.instance_list_path
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


return _M
