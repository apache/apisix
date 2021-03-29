local service = require "apisix.http.service"
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
local ipmatcher          = require("resty.ipmatcher")
local ipairs             = ipairs
local tostring           = tostring
local type               = type
local math_random        = math.random
local error              = error
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string_sub         = string.sub
local str_find           = core.string.find
local log                = core.log

local default_weight
local fetch_interval
local services = {}
local nacos_url
local nacos_access_token
local nacos_token_ttl = 18000

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
        username = {type = "string"},
        password = {type = "string"},
        fetch_interval = {type = "integer", minimum = 1, default = 30},
        prefix = {type = "string"},
        weight = {type = "integer", minimum = 0},
        timeout = {
            type = "object",
            properties = {
                connect = {type = "integer", minimum = 1, default = 2000},
                send = {type = "integer", minimum = 1, default = 2000},
                read = {type = "integer", minimum = 1, default = 5000},
            }
        },
    },
    required = {"host"}
}


local _M = {
    version = 0.1,
}

-- spring split function
string.split = function(s, p)
    local rt= {}
    string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
    return rt
end

-- http request
local function request(request_uri, method, path, query, body)
    log.info("nacos uri:", request_uri, ".")
    local url = request_uri .. path
    local headers = core.table.new(0, 5)
    headers['Connection'] = 'Keep-Alive'
    headers['Accept'] = 'application/json'
    if body then
    	headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end

    local httpc = http.new()
    local timeout = local_conf.discovery.nacos.timeout
    local connect_timeout = timeout and timeout.connect or 2000
    local send_timeout = timeout and timeout.send or 2000
    local read_timeout = timeout and timeout.read or 5000
    log.info("connect_timeout:", connect_timeout, ", send_timeout:", send_timeout,
            ", read_timeout:", read_timeout, ".")
    httpc:set_timeouts(connect_timeout, send_timeout, read_timeout)
    return httpc:request_uri(url, {
        version = 1.1,
        method = method,
        headers = headers,
        query = query,
        body = body,
        ssl_verify = false,
    })
end

-- fetch nacos accessToken, which is used in open-api
local function fetch_access_token(username, password)

    local body = "username=" .. username .. "&" .. "password=" .. password
    local res, err = request(nacos_url, "POST", "auth/login", nil, body)

    if not res then
        log.error("failed to fetch access_token", err)
        return
    end
    if not res.body or res.status ~= 200 then
        log.error("failed to fetch access_token, status = ", res.status)
        return
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        log.error("invalid response body: ", json_str, " err: ", err)
        return
    end
    return data.accessToken
end

-- nacos_url & nacos_access_token
local function init_info()
    local nacos = local_conf.discovery and local_conf.discovery.naocs
    
    -- pick one nacos cluster.
    local host =  local_conf.discovery.nacos.host
    local url = host[math_random(#host)]

    if local_conf.discovery.nacos.prefix then
        url = url .. local_conf.discovery.nacos.prefix
    end
    if string_sub(url, #url) ~= "/" then
        url = url .. "/"
    end

    local username = local_conf.discovery.nacos.username
    if not username then
        log.error("do not set nacos.username")
        return
    end

    local password = local_conf.discovery.nacos.password
    if not password then
        log.error("do not set nacos.password")
        return
    end
    
    nacos_url = url
    nacos_access_token = fetch_access_token(username, password)
end


local function parse_instances(instances)
    local up_instances = core.table.new(#instances, 0)
    for _, instance in pairs(instances) do
        core.table.insert(up_instances, {
            host = instance.ip,
            port = instance.port,
            weight = instance.weight or default_weight,
            metadata = instance.metadata,
        })
    end
    return up_instances
end

local function fetch_instances(service_name)
    if not service_name then
        log.error("service_name could not be nil")
        return
    end
    local namespaceId = "public"
    local groupName = "DEFAULT_GROUP"
    local serviceName = ""
    local arr = string.split(service_name, ":")
    if #arr == 3 then
        namespaceId = arr[1]
        groupName = arr[2]
        serviceName = arr[3]
    elseif #arr == 2 then
        namespaceId = arr[1]
        serviceName = arr[2]
    elseif #arr == 1 then
        serviceName = arr[1]
    else
        log.error("service_name is invalid")
        return
    end
    if not nacos_access_token then
        init_info()
    end
    local query = "accessToken=" .. nacos_access_token .. 
        "&" .. "namespaceId=" .. namespaceId ..
        "&" .. "groupName=" .. groupName ..
	    "&" .. "serviceName=" .. serviceName ..
	    "&" .. "healthyOnly=true"

    local res, err = request(nacos_url, "GET", "ns/instance/list", query)

    if not res then
        log.error("failed to fetch service instances", err)
        return
    end
    if not res.body or res.status ~= 200 then
        log.error("failed to fetch service instances, status = ", res.status)
        return
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        log.error("invalid response body: ", json_str, " err: ", err)
        return
    end
    return parse_instances(data.hosts)
end

local function fetch_full_instances(premature)
    if premature then
        return
    end

    if not services then
        return
    end
    
    for service_name, _ in pairs(services) do
        services[service_name] = fetch_instances(service_name)
    end
end

function _M.nodes(service_name)
    if not services or
        not services[service_name] then
        services[service_name] = fetch_instances(service_name)
    end
    return services[service_name]
end

-- init
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

    default_weight = local_conf.discovery.nacos.weight or 100
    log.info("default_weight:", default_weight, ".")

    fetch_interval = local_conf.discovery.nacos.fetch_interval or 30
    log.info("fetch_interval:", fetch_interval, ".")

    ngx_timer_at(0, init_info)
    ngx_timer_every(nacos_token_ttl, init_info)
    ngx_timer_every(fetch_interval, fetch_full_instances)
end


return _M
