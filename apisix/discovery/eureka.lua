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
local socket_http        = require("socket.http")
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
local applications

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


local function service_info()
    local host = local_conf.discovery and
        local_conf.discovery.eureka and local_conf.discovery.eureka.host
    if not host then
        log.error("do not set eureka.host")
        return
    end

    local basic_auth
    -- TODO Add health check to get healthy nodes.
    local url = host[math_random(#host)]
    local auth_idx = str_find(url, "@")
    if auth_idx then
        local protocol_idx = str_find(url, "://")
        local protocol = string_sub(url, 1, protocol_idx + 2)
        local user_and_password = string_sub(url, protocol_idx + 3, auth_idx - 1)
        local other = string_sub(url, auth_idx + 1)
        url = protocol .. other
        basic_auth = "Basic " .. ngx.encode_base64(user_and_password)
    end
    if local_conf.discovery.eureka.prefix then
        url = url .. local_conf.discovery.eureka.prefix
    end
    if string_sub(url, #url) ~= "/" then
        url = url .. "/"
    end

    return url, basic_auth
end


local function request(request_uri, basic_auth, method, path, query)
    log.info("eureka uri:", request_uri, ".")
    local url = request_uri .. path
    local headers = core.table.new(0, 5)
    headers['Connection'] = 'Keep-Alive'
    headers['Accept'] = 'application/json'

    if basic_auth then
        headers['Authorization'] = basic_auth
    end

    local request_body = query
    if query and type(query) == 'table' then
        request_body = core.json.encode(query, { indent = true })
        headers["Content-Type"] = "application/json"
    end

    if request_body then
        headers["Content-Length"] = #request_body
    end

    local response_body = {}
    local _, code = socket_http.request {
        url = url,
        method = method,
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }

    local resp_table = core.table.concat(response_body)
    local data = core.json.decode(resp_table)
    return code, data
end


local function parse_instance(instance)
    local status = instance.status
    local overridden_status = instance.overriddenstatus or instance.overriddenStatus
    if overridden_status and overridden_status ~= "UNKNOWN" then
        status = overridden_status
    end

    if status ~= "UP" then
        return
    end
    local port
    if tostring(instance.port["@enabled"]) == "true" and instance.port["$"] then
        port = instance.port["$"]
        -- secure = false
    end
    if tostring(instance.securePort["@enabled"]) == "true" and instance.securePort["$"] then
        port = instance.securePort["$"]
        -- secure = true
    end
    local ip = instance.ipAddr
    if not ipmatcher.parse_ipv4(ip) and
            not ipmatcher.parse_ipv6(ip) then
        log.error(instance.app, " service ", instance.hostName, " node IP ", ip,
                " is invalid(must be IPv4 or IPv6).")
        return
    end
    return ip, port, instance.metadata
end


local function fetch_full_registry(premature)
    if premature then
        return
    end

    local request_uri, basic_auth = service_info()
    if not request_uri then
        return
    end

    local code, data = request(request_uri, basic_auth, "GET", "apps")
    if not data or code ~= 200 then
        log.error("failed to fetch registry, status = ", code, ",response body: ", core.json.encode(data))
        return
    end

    local apps = data.applications.application
    local up_apps = core.table.new(0, #apps)
    for _, app in ipairs(apps) do
        for _, instance in ipairs(app.instance) do
            local ip, port, metadata = parse_instance(instance)
            if ip and port then
                local nodes = up_apps[app.name]
                if not nodes then
                    nodes = core.table.new(#app.instance, 0)
                    up_apps[app.name] = nodes
                end
                core.table.insert(nodes, {
                    host = ip,
                    port = port,
                    weight = metadata and metadata.weight or default_weight,
                    metadata = metadata,
                })
                if metadata then
                    -- remove useless data
                    metadata.weight = nil
                end
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
    if not local_conf.discovery.eureka or
        not local_conf.discovery.eureka.host or #local_conf.discovery.eureka.host == 0 then
        error("do not set eureka.host")
        return
    end

    local ok, err = core.schema.check(schema, local_conf.discovery.eureka)
    if not ok then
        error("invalid eureka configuration: " .. err)
        return
    end
    default_weight = local_conf.discovery.eureka.weight or 100
    log.info("default_weight:", default_weight, ".")
    local fetch_interval = local_conf.discovery.eureka.fetch_interval or 30
    log.info("fetch_interval:", fetch_interval, ".")
    fetch_full_registry()
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


function _M.dump_data()
    return {config = local_conf.discovery.eureka, services = applications or {}}
end


return _M
