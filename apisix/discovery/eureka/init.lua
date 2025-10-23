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
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local string_sub         = string.sub
local str_find           = core.string.find
local log                = core.log
local semaphore = require("ngx.semaphore")

local default_weight
local applications
local init_sema
local initial_fetched = false

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


local function request(request_uri, basic_auth, method, path, query, body)
    log.info("eureka uri:", request_uri, ".")
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
    local timeout = local_conf.discovery.eureka.timeout
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


local function build_endpoints()
    local host_list = local_conf.discovery and local_conf.discovery.eureka and local_conf.discovery.eureka.host
    if not host_list or #host_list == 0 then
        log.error("do not set eureka.host")
        return nil
    end

    local endpoints = core.table.new(#host_list, 0)
    for _, h in ipairs(host_list) do
        local url = h
        local basic_auth
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
        core.table.insert(endpoints, { url = url, auth = basic_auth })
    end
    return endpoints
end


local function fetch_full_registry(premature)
    if premature then
        return
    end

    -- 遍历所有 eureka 端点，直到成功
    local endpoints = build_endpoints()
    if not endpoints or #endpoints == 0 then
        return
    end

    local res, err
    local used_endpoint
    local start = math_random(#endpoints)
    for i = 0, #endpoints - 1 do
        local ep = endpoints[((start + i) % #endpoints) + 1]
        log.info("eureka uri:", ep.url, ".")
        local r, e = request(ep.url, ep.auth, "GET", "apps")
        if r and r.body and r.status == 200 then
            res = r
            used_endpoint = ep
            break
        end
        log.warn("failed to fetch registry from ", ep.url, ": ", e or (r and ("status=" .. tostring(r.status)) or "unknown"))
    end

    if not res then
        log.error("failed to fetch registry from all eureka hosts")
        return
    end

    local json_str = res.body
    local data, derr = core.json.decode(json_str)
    if not data then
        log.error("invalid response body: ", json_str, " err: ", derr)
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
                    metadata.weight = nil
                end
            end
        end
    end
    applications = up_apps
    log.info("successfully updated service registry, services count=",
             core.table.nkeys(up_apps), "; source=", used_endpoint and used_endpoint.url or "unknown")
    if not initial_fetched then
        initial_fetched = true
        if init_sema then
            init_sema:post(1)
        end
    end
end


function _M.nodes(service_name)
    if not applications then
        if init_sema then
            local ok, err = init_sema:wait(3)
            if not ok then
                log.warn("wait eureka initial fetch timeout: ", err)
            end
        end
    end

    if not applications then
        log.error("failed to fetch nodes for : ", service_name)
        return
    end

    return applications[service_name]
end


-- 注释掉文件缓存相关依赖与变量，避免写盘/读盘
-- local core_io = require("apisix.core.io")
-- local io_open = io.open
-- local cache_file = ngx.config.prefix() .. "logs/eureka_registry.json"
-- local save_registry_cache
-- local load_registry_cache
-- 将文件缓存函数整体注释掉，避免写盘与读盘
--[[
local function save_registry_cache(apps)
    local body, err = core.json.encode({ applications = apps, ts = ngx.now() })
    if not body then
        log.error("encode eureka registry cache failed: ", err)
        return
    end
    local f, ferr = io_open(cache_file, "w")
    if not f then
        log.error("open eureka registry cache file failed: ", ferr,
                  ", path: ", cache_file)
        return
    end
    f:write(body)
    f:close()
end

local function load_registry_cache()
    local body = core_io.get_file(cache_file)
    if not body then
        return nil, "no cache file"
    end
    local data, err = core.json.decode(body)
    if not data or not data.applications then
        return nil, "invalid cache format: " .. (err or "")
    end
    return data.applications
end
]]
-- 移除保存缓存调用
-- save_registry_cache(up_apps)


function _M.init_worker()
    default_weight = local_conf.discovery.eureka.weight or 100
    log.info("default_weight:", default_weight, ".")
    local fetch_interval = local_conf.discovery.eureka.fetch_interval or 30
    log.info("fetch_interval:", fetch_interval, ".")
    init_sema = semaphore.new()

    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


function _M.dump_data()
    return {config = local_conf.discovery.eureka, services = applications or {}}
end


return _M
