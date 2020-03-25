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
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string_sub         = string.sub
local string_find        = string.find
local log                = core.log

local applications
local useragent = 'ngx_lua-apisix/v' .. core.version.VERSION

local _M = {
    version = 1.0,
}


local function service_info()
    if not local_conf.eureka or not local_conf.eureka.urls then
        log.error("do not set eureka.urls")
        return
    end

    local urls = local_conf.eureka.urls
    local basic_auth
    -- TODO Add health check to get healthy nodes.
    local url = urls[math.random(#urls)]
    local user_and_password_idx = string_find(url, "@", 1, true)
    if user_and_password_idx then
        local protocol_header_idx = string_find(url, "://", 1, true)
        local protocol_header = string_sub(url, 1, protocol_header_idx + 2)
        local user_and_password = string_sub(url, protocol_header_idx + 3, user_and_password_idx - 1)
        local other = string_sub(url, user_and_password_idx + 1)
        url = protocol_header .. other
        basic_auth = "Basic " .. ngx.encode_base64(user_and_password)
    end

    if string_sub(url, #url) ~= "/" then
        url = url .. "/"
    end

    return url, basic_auth
end


local function request(request_uri, basic_auth, method, path, query, body)
    local url = request_uri .. path
    local headers = core.table.new(0, 5)
    headers['User-Agent'] = useragent
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
    local timeout = local_conf.eureka.timeout
    local connect_timeout = timeout and timeout.connect or 2000
    local send_timeout = timeout and timeout.send or 2000
    local read_timeout = timeout and timeout.read or 5000
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


local function fetch_full_registry(premature)
    if premature then
        return
    end

    local request_uri, basic_auth = service_info()
    if not request_uri then
        return
    end

    local res, err = request(request_uri, basic_auth, "GET", "apps")
    if not res then
        log.error("failed to fetch registry", err)
        return
    end

    if not res.body or res.status ~= 200 then
        log.error("failed to fetch registry, status = ", res.status)
        return
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        log.error("invalid response body: ", json_str, " err: ", err)
        return
    end
    local apps = data.applications.application
    local up_apps = core.table.new(0, #apps)
    for _, app in ipairs(apps) do
        local nodes = up_apps[app.name]
        if not nodes then
            nodes = core.table.new(#app.instance, 0)
            up_apps[app.name] = nodes
        end
        for _, instance in ipairs(app.instance) do
            local status = instance.status
            local overridden_status = instance.overriddenstatus
            if overridden_status and "UNKNOWN" ~= overridden_status then
                status = overridden_status
            end
            if status == "UP" then
                local port
                if tostring(instance.port["@enabled"]) == "true" and instance.port["$"] then
                    port = instance.port["$"]
                    -- secure = false
                end
                if tostring(instance.securePort["@enabled"]) == "true" and instance.securePort["$"] then
                    port = instance.securePort["$"]
                    -- secure = true
                end
                -- TODO use metadata
                nodes[instance.ipAddr .. ":" .. port] = 1
            end
        end
    end
    applications = up_apps
end


function _M.nodes(service_name)
    if not applications then
        log.error("failed to fetch instances for : ", service_name)
        return nil
    end

    return applications[service_name]
end


function _M.init_worker()
    if not local_conf.eureka or not local_conf.eureka.urls then
        error("do not set eureka.urls")
        return
    end
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(30, fetch_full_registry)
end

return _M
