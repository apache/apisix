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

local core = require("apisix.core")
local http = require('resty.http')
local ngx = ngx
local utils = require("apisix.discovery.nacos.utils")
local string             = string
local string_sub         = string.sub
local str_byte           = string.byte
local str_find           = core.string.find
local ngx_timer_at = ngx.timer.at
local math_random  = math.random
local shdict_name = "nacos"
if ngx.config.subsystem == "stream" then
    shdict_name = shdict_name .. "-stream"
end

local nacos_dict = ngx.shared[shdict_name]
local ngx = ngx
local ngx_re             = require('ngx.re')
local NACOS_LOGIN_PATH = "/auth/login"
local NACOS_INSTANCE_PATH = "/ns/instance/list"
local inspect = require("inspect")
local _M = {}


local function _request(method, uri, params, headers, body, options)
    local url = uri
    core.log.warn("PARAM IS ", inspect(params))
    if params ~= nil and params ~= {} then
        url = uri .. "?" .. utils.generate_request_params(params)
    end
    core.log.warn("final uri: ", url)
    local httpc = http.new()
    local timeout = options and options.timeout or {}
    local connect_timeout = timeout.connect and timeout.connect * 1000 or 2000
    local read_timeout = timeout.read and timeout.read * 1000 or 2000
    local write_timeout = timeout.write and timeout.write * 1000 or 5000

    httpc:set_timeouts(connect_timeout, read_timeout, write_timeout )
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = headers,
        body = body,
        ssl_verify = false,
    })

    if not res then
        core.log.warn("ERR ASHISH ", err)
        return nil, err
    end

    if not res.body or res.status ~= 200 then
        return nil, 'status = ' .. res.status
    end

    core.log.info("request to nacos, uri: ", url, "response: ", res.body)

    local data, err = core.json.decode(res.body)
    if not data then
        return nil, err
    end

    return data
end


local function get_base_uri(hosts)
    local host = hosts
    core.log.warn("HOSTS ", inspect(host))
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
    core.log.warn("RETURNED URL2 ", url)
    return url, username, password
end

local function request_login(self, host, username, password)
    core.log.warn("USERNAME AND PASS ARE ", username, password, " AND HOST ", host)
    local params = {
       ["username"] = username,
       ["password"] = password,
    }
    -- backward compat: NACOS_LOGIN_PATH starts with "/" so we need to remove the last "/" from prefix
    if string_sub(self.config.prefix, -1) == "/" then
        self.config.prefix = string_sub(self.config.prefix, 1, -2)
    end
    local uri = host .. self.config.prefix .. NACOS_LOGIN_PATH

    local headers = {
        ["Content-Type"] ="application/x-www-form-urlencoded"
    }
    
    local resp, err = _request("POST", uri, nil, headers, utils.generate_request_params(params), {timeout=self.config.timeout})
    if not resp then
        core.log.error("failed to fetch token from nacos, uri: ", uri, " err: ", err)
        return ""
    end
    core.log.warn("RETURNING ACCESS TOKEN", resp.accessToken)
    return resp.accessToken
end


local function request_instance_list(self, params, host)
    core.log.warn("FIRST CONCATENATAE ", inspect(host))
    -- backward compat: NACOS_INSTANCE_PATH starts with "/" so we need to remove the last "/" from prefix
    if string_sub(self.config.prefix, -1) == "/" then
        self.config.prefix = string_sub(self.config.prefix, 1, -2)
    end
    local uri = host .. self.config.prefix .. NACOS_INSTANCE_PATH

    local resp, err = _request("GET", uri, params)
    if not resp then
        core.log.error("failed to fetch instances list from nacos, uri: ", uri, " err: ", err)
        return {}
    end
    core.log.warn("RETURNED HOSTS: ", inspect(resp.hosts), " for uri", uri)
    return resp.hosts or {}
end


local function fetch_instances(self, serv)
    local config = self.config

    local params = {
        ["namespaceId"] = serv.namespace_id or "",
        ["groupName"] = serv.group_name or "DEFAULT_GROUP",
        ["serviceName"] = serv.name,
        ["healthyOnly"] = "true"
    }

    local auth = config.auth or {}
    -- for backward compat:
    -- In older method, we passed username and password inside of host
    -- In new method its passed separately
    local username, password, host
    if config.old_conf then
        -- extract username and password from host
        host, username, password = get_base_uri(config.hosts)
    else
        host = config.hosts[math_random(#config.hosts)]
        if (auth.username and auth.username ~= "") and (auth.password and auth.password ~= "") then
            username = auth.username
            password = auth.password
         end
    end
    core.log.warn("USERNAME AND PASSWORD ", username, password, " AND HOST ", host)
    if username and username ~= "" and password and password ~= "" then
        local token = request_login(self, host, username, password)
        core.log.warn("TOKEN IS ", token)
        params["accessToken"] = token
    end

    if auth.token and auth.token ~= "" then
        params["accessToken"] = auth.token
    end

    if (auth.access_key and auth.access_key ~= "") and (auth.secret_key and auth.secret_key ~= "") then
       local ak, data, signature = utils.generate_signature(serv.group_name, serv.name, auth.access_key, auth.secret_key)
       params["ak"] = ak
       params["data"] = data
       params["signature"] = signature
    end

    local instances = request_instance_list(self, params, host)
    local nodes = {}
    for _, instance in ipairs(instances) do
        local node = {
            host = instance.ip,
            port = instance.port,
            weight = instance.weight or self.config.default_weight,
            metadata = instance.metadata,
        }

        core.table.insert(nodes, node)
    end
    core.log.warn("NODE RETURNED BY fetch_instances: ", inspect(nodes))
    return nodes
end


local function fetch_full_registry(self)
    return function (premature)
        if premature then
            return
        end

        local config = self.config
        local services_in_use = utils.get_nacos_services(config.id)
        for _, serv in ipairs(services_in_use) do
            if self.stop_flag then
                core.log.error("nacos client is exited, id: ", config.id)
                return
            end

            local nodes = self:fetch_instances(serv)
            core.log.warn("NODES ARE", inspect(nodes), "FOR service ", inspect(serv))
            if #nodes > 0 then
                local content = core.json.encode(nodes)
                local key = utils.generate_key(serv.namespace_id, serv.group_name, serv.name)
                core.log.warn("[SET]", "key=", key,"; CONTENT=",content)
                nacos_dict:set(key, content, self.config.fetch_interval * 10)
             end
        end

        ngx_timer_at(self.config.fetch_interval, self:fetch_full_registry())
    end
end


local function stop(self)
    self.stop_flag = true

    if self.checker then
        self.checker:clear()
    end
end


local function start(self)
    ngx_timer_at(0, self:fetch_full_registry())
end


function _M.new(config)
    local version = ngx.md5(core.json.encode(config, true))

    local client = {
        id = config.id,
        version = version,
        config = config,
        stop_flag = false,

        start = start,
        stop = stop,
        fetch_instances = fetch_instances,
        fetch_full_registry = fetch_full_registry,
    }

    if config.check then
        local health_check = require("resty.healthcheck")
        local checker = health_check.new({
            name = config.id,
            shm_name = "nacos",
            checks = config.check
        })

        local ok, err = checker:add_target(config.check.active.host, config.check.active.port, nil, false)
        if not ok then
            core.log.error("failed to add health check target", core.json.encode(config), " err: ", err)
        else
            core.log.info("success to add health checker, id ", config.id, " host ", config.check.active.host, " port ", config.check.active.port)
            client.checker = checker
        end
    end

    return client
end

return _M
