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
local service            = require("apisix.discovery.service")
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


local function split(self, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c)
        fields[#fields + 1] = c
    end)
    return fields
end


local function service_info()
    if not local_conf.eureka or not local_conf.eureka.urls then
        log.error("do not set eureka.url")
        return
    end
    local service_url = local_conf.eureka.urls
    local urls = split(service_url, [[,]])
    local basic_auth
    local url = urls[math.random(#urls)]
    local user_and_password_idx = string_find(url, "@")
    if user_and_password_idx then
        local protocol_header_idx = string_find(url, "://")
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
    httpc:set_timeouts(2000, 2000, 5000)
    return httpc:request_uri(url, {
        version = 1.1,
        method = method,
        headers = headers,
        query = query,
        body = body,
        ssl_verify = false,
    })
end


local function get_and_store_full_registry(premature)
    if premature then
        return
    end
    local request_uri, basic_auth = service_info()
    if not request_uri then
        return
    end
    local res, err = request(request_uri, basic_auth, "GET", "apps", nil, nil)
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
    end
    local apps = data.applications.application
    local up_apps = core.table.new(0, #apps)
    for _, app in ipairs(apps) do
        local app_service = up_apps[app.name]
        if not app_service then
            app_service = service:new(#app.instance)
            up_apps[app.name] = app_service
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
                app_service.value.nodes[instance.ipAddr .. ":" .. port] = 1
            end
        end
    end
    applications = up_apps
end


function _M.get_service(up_id)
    if not applications then
        log.error("failed to fetch instances for : ", up_id)
        return nil
    end

    return applications[up_id]
end


function _M.init_worker()
    if not local_conf.eureka or not local_conf.eureka.urls then
        error("do not set eureka.url")
        return
    end
    ngx_timer_at(0, get_and_store_full_registry)
    ngx_timer_every(30, get_and_store_full_registry)
end

return _M
