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
local type               = type
local math_random        = math.random
local error              = error
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string_sub         = string.sub
local string_find        = string.find
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
        namespace = {type = "string", default = "public"},
        group = {type = "string", default = "DEFAULT_GROUP"},
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
    local host = local_conf.nacos and local_conf.nacos.host
    if not host then
        log.error("do not set nacos.host")
        return
    end

    local basic_auth
    -- TODO Add health check to get healthy nodes.
    local url = host[math_random(#host)]
    local auth_idx = string_find(url, "@", 1, true)
    if auth_idx then
        local protocol_idx = string_find(url, "://", 1, true)
        local protocol = string_sub(url, 1, protocol_idx + 2)
        local user_and_password = string_sub(url, protocol_idx + 3, auth_idx - 1)
        local other = string_sub(url, auth_idx + 1)
        url = protocol .. other
        basic_auth = "Basic " .. ngx.encode_base64(user_and_password)
    end
    if local_conf.nacos.prefix then
        url = url .. local_conf.nacos.prefix
    end
    if string_sub(url, #url) ~= "/" then
        url = url .. "/"
    end

    return url, basic_auth
end


local function request(request_uri, basic_auth, method, path, query, body)
    log.info("nacos uri:", request_uri, ".")
    local url = request_uri .. path
    local headers = core.table.new(0, 5)
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
    local timeout = local_conf.nacos.timeout
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


local function fetch_instance(service)
    if not service then
	return
    end

    local request_uri, basic_auth = service_info()
    if not request_uri then
        return
    end

    -- nacos default config
    local namespace = local_conf.nacos.namespace or "public"

    -- get instance by service
    local getInstanceQuery="namespaceId=" .. namespace .. "&serviceName=" .. service
    local res, err = request(request_uri, basic_auth, "GET", "v1/ns/instance/list",getInstanceQuery)
    if not res then
        log.error("failed to fetch instance for " .. service , err)
        return
    end

    if not res.body or res.status ~= 200 then
        log.error("failed to fetch  services , status = ", res.status)
        return
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        log.error("get instance for "..service..",invalid response body: ",json_str, " err: ", err)
        return
    end


    local instanceInfo = {}
    -- enable not register to apisix
    local serviceMetadata = data.metadata
    if serviceMetadata["apisix.gateway.registration"] == "false" then
        log.info("skip register service: ", service)
        return instanceInfo
    end

    local hosts = data.hosts
    for _, host in ipairs(hosts) do
        -- add serviceName and weight
        -- weigth is required , when get node for service by apisix
        local innerInstanceInfo = core.table.new(0, #host + 2)
        innerInstanceInfo["serviceName"] = host.serviceName
        innerInstanceInfo["weight"] = host.weight or  host.metadata["weight"]  or default_weight
        innerInstanceInfo["host"]= host.ip
        innerInstanceInfo["port"] = host.port
        innerInstanceInfo["metadata"] = host.metadata
        if innerInstanceInfo["metadata"]["apisix.gateway.registration"] ~= "false" then
                core.table.insert(instanceInfo, innerInstanceInfo)
        end
    end

    return instanceInfo
end


local function fetch_all_instance(premature)
    if premature then
        return
    end

    local request_uri, basic_auth = service_info()
    if not request_uri then
        return
    end

    local namespace = local_conf.nacos.namespace or "public"
    local group = local_conf.nacos.group or "DEFAULT_GROUP"

    -- get all service
    local getServiceQuery="pageNo=1&pageSize=1000".."&groupName="..group.."&namespaceId="..namespace
    local res, err = request(request_uri, basic_auth, "GET", "v1/ns/service/list", getServiceQuery)
    if not res then
        log.error("failed to fetch services ", err)
        return
    end

    if not res.body or res.status ~= 200 then
        log.error("failed to fetch  services , status = ", res.status)
        log.error("failed to fetch  services , resp page = ", res.body)
        return
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        log.error("get all services from nacos, invalid response body: ", json_str, " err: ", err)
        return
    end

    local services = data.doms
    local servicesInstances = core.table.new(0, #services)
    for _, service in ipairs(services) do
        local instanceInfo = fetch_instance(service)
        if next(instanceInfo) ~= nil then
		servicesInstances[service] = {}
		for _, instance in ipairs(instanceInfo) do
			core.table.insert(servicesInstances[service],instance)
		end
	end
    end

    applications = servicesInstances
end


function _M.nodes(service_name)
    if not applications then
        log.error("failed to fetch nodes for: ", service_name)
        return
    end
    return applications[service_name]
end


function _M.init_worker()
    if not local_conf.nacos or not local_conf.nacos.host or #local_conf.nacos.host == 0 then
        error("do not set nacos.host")
        return
    end

    local ok, err = core.schema.check(schema, local_conf.nacos)
    if not ok then
        error("invalid nacos configuration: " .. err)
        return
    end
    default_weight = local_conf.nacos.weight or 100
    log.info("default_weight:", default_weight, ".")
    local fetch_interval = local_conf.nacos.fetch_interval or 30
    log.info("fetch_interval:", fetch_interval, ".")
    ngx_timer_at(0, fetch_all_instance)
    ngx_timer_every(fetch_interval, fetch_all_instance)
end


return _M
