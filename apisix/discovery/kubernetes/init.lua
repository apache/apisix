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

local ngx = ngx
local ipairs = ipairs
local pairs = pairs
local string = string
local tonumber = tonumber
local tostring = tostring
local os = os
local error = error
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local local_conf = require("apisix.core.config_local").local_conf()
local kubernetes = require("apisix.kubernetes")
local endpoint_dict = ngx.shared.discovery

local default_weight = 0

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local endpoint_buffer = {}
local empty_table = {}

local function sort_cmp(left, right)
    if left.host ~= right.host then
        return left.host < right.host
    end
    return left.port < right.port
end

local function on_endpoint_modified(endpoint)
    core.log.debug(core.json.encode(endpoint, true))
    core.table.clear(endpoint_buffer)

    local subsets = endpoint.subsets
    for _, subset in ipairs(subsets or empty_table) do
        if subset.addresses ~= nil then
            local addresses = subset.addresses
            for _, port in ipairs(subset.ports or empty_table) do
                local port_name
                if port.name then
                    port_name = port.name
                elseif port.targetPort then
                    port_name = tostring(port.targetPort)
                else
                    port_name = tostring(port.port)
                end

                local nodes = endpoint_buffer[port_name]
                if nodes == nil then
                    nodes = core.table.new(0, #subsets * #addresses)
                    endpoint_buffer[port_name] = nodes
                end

                for _, address in ipairs(subset.addresses) do
                    core.table.insert(nodes, {
                        host = address.ip,
                        port = port.port,
                        weight = default_weight
                    })
                end
            end
        end
    end

    for _, ports in pairs(endpoint_buffer) do
        for _, nodes in pairs(ports) do
            core.table.sort(nodes, sort_cmp)
        end
    end

    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    local endpoint_content = core.json.encode(endpoint_buffer, true)
    local endpoint_version = ngx.crc32_long(endpoint_content)

    local _, err
    _, err = endpoint_dict:safe_set(endpoint_key .. "#version", endpoint_version)
    if err then
        core.log.error("set endpoint version into discovery DICT failed, ", err)
        return
    end
    _, err = endpoint_dict:safe_set(endpoint_key, endpoint_content)
    if err then
        core.log.error("set endpoint into discovery DICT failed, ", err)
        endpoint_dict:delete(endpoint_key .. "#version")
    end
end

local function on_endpoint_deleted(endpoint)
    core.log.debug(core.json.encode(endpoint, true))
    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    endpoint_dict:delete(endpoint_key .. "#version")
    endpoint_dict:delete(endpoint_key)
end

local function set_namespace_selector(conf, informer)
    local ns = conf.namespace_selector
    if ns == nil then
        informer.namespace_selector = nil
    elseif ns.equal then
        informer.field_selector = "metadata.namespace%3D" .. ns.equal
        informer.namespace_selector = nil
    elseif ns.not_equal then
        informer.field_selector = "metadata.namespace%21%3D" .. ns.not_equal
        informer.namespace_selector = nil
    elseif ns.match then
        informer.namespace_selector = function(self, namespace)
            local match = conf.namespace_selector.match
            local m, err
            for _, v in ipairs(match) do
                m, err = ngx.re.match(namespace, v, "j")
                if m and m[0] == namespace then
                    return true
                end
                if err then
                    core.log.error("ngx.re.match failed: ", err)
                end
            end
            return false
        end
    elseif ns.not_match then
        informer.namespace_selector = function(self, namespace)
            local not_match = conf.namespace_selector.not_match
            local m, err
            for _, v in ipairs(not_match) do
                m, err = ngx.re.match(namespace, v, "j")
                if m and m[0] == namespace then
                    return false
                end
                if err then
                    return false
                end
            end
            return true
        end
    end
end

local function read_env(key)
    if #key > 3 then
        local a, b = string.byte(key, 1, 2)
        local c = string.byte(key, #key, #key)
        -- '$', '{', '}' == 36,123,125
        if a == 36 and b == 123 and c == 125 then
            local env = string.sub(key, 3, #key - 1)
            local val = os.getenv(env)
            if not val then
                return false, nil, "not found environment variable " .. env
            end
            return true, val, nil
        end
    end
    return true, key, nil
end

local function read_conf(conf, apiserver)

    apiserver.schema = conf.service.schema

    local ok, value, message
    ok, value, message = read_env(conf.service.host)
    if not ok then
        return false, message
    end

    apiserver.host = value
    if apiserver.host == "" then
        return false, "get empty host value"
    end

    ok, value, message = read_env(conf.service.port)
    if not ok then
        return false, message
    end

    apiserver.port = tonumber(value)
    if not apiserver.port or apiserver.port <= 0 or apiserver.port > 65535 then
        return false, "get invalid port value: " .. apiserver.port
    end

    -- we should not check if the apiserver.token is empty here
    if conf.client.token then
        ok, value, message = read_env(conf.client.token)
        if not ok then
            return false, message
        end
        apiserver.token = value
    elseif conf.client.token_file and conf.client.token_file ~= "" then
        ok, value, message = read_env(conf.client.token_file)
        if not ok then
            return false, message
        end
        local apiserver_token_file = value

        apiserver.token, message = util.read_file(apiserver_token_file)
        if not apiserver.token then
            return false, message
        end
    else
        return false, "invalid kubernetes discovery configuration:" ..
                "should set one of [client.token,client.token_file] but none"
    end

    default_weight = conf.default_weight or 50

    return true, nil
end

local function create_endpoint_lrucache(endpoint_key, endpoint_port)
    local endpoint_content, _, _ = endpoint_dict:get_stale(endpoint_key)
    if not endpoint_content then
        core.log.error("get empty endpoint content from discovery DIC, this should not happen ",
                endpoint_key)
        return nil
    end

    local endpoint, _ = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.error("decode endpoint content failed, this should not happen, content: ",
                endpoint_content)
    end

    return endpoint[endpoint_port]
end

local _M = {
    version = "0.0.1"
}

function _M.nodes(service_name)
    local pattern = "^(.*):(.*)$"  -- namespace/name:port_name
    local match, _ = ngx.re.match(service_name, pattern, "jo")
    if not match then
        core.log.info("get unexpected upstream service_name:　", service_name)
        return nil
    end

    local endpoint_key = match[1]
    local endpoint_port = match[2]
    local endpoint_version, _, _ = endpoint_dict:get_stale(endpoint_key .. "#version")
    if not endpoint_version then
        core.log.info("get empty endpoint version from discovery DICT ", endpoint_key)
        return nil
    end
    return endpoint_lrucache(service_name, endpoint_version,
            create_endpoint_lrucache, endpoint_key, endpoint_port)
end

function _M.init_worker()
    if process.type() ~= "privileged agent" then
        return
    end

    local ok, err = read_conf(local_conf.discovery.kubernetes, kubernetes.apiserver)
    if not ok then
        error(err)
        return
    end

    local endpoint_informer = kubernetes.informer_factory.new("", "v1",
            "Endpoints", "endpoints", "")

    set_namespace_selector(local_conf.discovery.kubernetes, endpoint_informer)

    endpoint_informer.on_added = function(self, object, drive)
        if self.namespace_selector ~= nil then
            if self:namespace_selector(object.metadata.namespace) then
                on_endpoint_modified(object)
            end
        else
            on_endpoint_modified(object)
        end
    end

    endpoint_informer.on_modified = endpoint_informer.on_added

    endpoint_informer.on_deleted = function(self, object)
        if self.namespace_selector ~= nil then
            if self:namespace_selector(object.metadata.namespace) then
                on_endpoint_deleted(object)
            end
        else
            on_endpoint_deleted(object)
        end
    end

    endpoint_informer.pre_list = function(self)
        endpoint_dict:flush_all()
    end

    endpoint_informer.post_list = function(self)
        endpoint_dict:flush_expired()
    end

    local timer_runner
    timer_runner = function(premature, informer)
        if informer:list_watch() then
            local retry_interval = 40
            ngx.sleep(retry_interval)
        end
        ngx.timer.at(0, timer_runner, informer)
    end

    ngx.timer.at(0, timer_runner, endpoint_informer)
end

return _M
