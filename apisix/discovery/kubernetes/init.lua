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
local pcall = pcall
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local local_conf = require("apisix.core.config_local").local_conf()
local informer_factory = require("apisix.discovery.kubernetes.informer_factory")

local endpoint_dict

local default_weight

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local endpoint_buffer = {}

local function sort_nodes_cmp(left, right)
    if left.host ~= right.host then
        return left.host < right.host
    end

    return left.port < right.port
end


local function on_endpoint_modified(informer, endpoint)
    if informer.namespace_selector and
            not informer:namespace_selector(endpoint.metadata.namespace) then
        return
    end

    core.log.debug(core.json.delay_encode(endpoint))
    core.table.clear(endpoint_buffer)

    local subsets = endpoint.subsets
    for _, subset in ipairs(subsets or {}) do
        if subset.addresses then
            local addresses = subset.addresses
            for _, port in ipairs(subset.ports or {}) do
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
            core.table.sort(nodes, sort_nodes_cmp)
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


local function on_endpoint_deleted(informer, endpoint)
    if informer.namespace_selector and
            not informer:namespace_selector(endpoint.metadata.namespace) then
        return
    end

    core.log.debug(core.json.delay_encode(endpoint))
    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    endpoint_dict:delete(endpoint_key .. "#version")
    endpoint_dict:delete(endpoint_key)
end


local function pre_list(informer)
    endpoint_dict:flush_all()
end


local function post_list(informer)
    endpoint_dict:flush_expired()
end


local function setup_label_selector(conf, informer)
    informer.label_selector = conf.label_selector
end


local function setup_namespace_selector(conf, informer)
    local ns = conf.namespace_selector
    if ns == nil then
        informer.namespace_selector = nil
        return
    end

    if ns.equal then
        informer.field_selector = "metadata.namespace=" .. ns.equal
        informer.namespace_selector = nil
        return
    end

    if ns.not_equal then
        informer.field_selector = "metadata.namespace!=" .. ns.not_equal
        informer.namespace_selector = nil
        return
    end

    if ns.match then
        informer.namespace_selector = function(self, namespace)
            local match = conf.namespace_selector.match
            local m, err
            for _, v in ipairs(match) do
                m, err = ngx.re.match(namespace, v, "jo")
                if m and m[0] == namespace then
                    return true
                end
                if err then
                    core.log.error("ngx.re.match failed: ", err)
                end
            end
            return false
        end
        return
    end

    if ns.not_match then
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
        return
    end
end


local function read_env(key)
    if #key > 3 then
        local a, b = string.byte(key, 1, 2)
        local c = string.byte(key, #key, #key)
        -- '$', '{', '}' == 36,123,125
        if a == 36 and b == 123 and c == 125 then
            local env = string.sub(key, 3, #key - 1)
            local value = os.getenv(env)
            if not value then
                return nil, "not found environment variable " .. env
            end
            return value, nil
        end
    end

    return key
end


local function get_apiserver(conf)
    local apiserver = {
        schema = "",
        host = "",
        port = "",
        token = ""
    }

    apiserver.schema = conf.service.schema
    if apiserver.schema ~= "http" and apiserver.schema ~= "https" then
        return nil, "service.schema should set to one of [http,https] but " .. apiserver.schema
    end

    local err
    apiserver.host, err = read_env(conf.service.host)
    if err then
        return nil, err
    end

    if apiserver.host == "" then
        return nil, "service.host should set to non-empty string"
    end

    local port
    port, err = read_env(conf.service.port)
    if err then
        return nil, err
    end

    apiserver.port = tonumber(port)
    if not apiserver.port or apiserver.port <= 0 or apiserver.port > 65535 then
        return nil, "invalid port value: " .. apiserver.port
    end

    if conf.client.token then
        apiserver.token, err = read_env(conf.client.token)
        if err then
            return nil, err
        end
    elseif conf.client.token_file and conf.client.token_file ~= "" then
        local file
        file, err = read_env(conf.client.token_file)
        if err then
            return nil, err
        end

        apiserver.token, err = util.read_file(file)
        if err then
            return nil, err
        end
    else
        return nil, "one of [client.token,client.token_file] should be set but none"
    end

    if apiserver.schema == "https" and apiserver.token == "" then
        return nil, "apiserver.token should set to non-empty string when service.schema is https"
    end

    return apiserver
end


local function create_endpoint_lrucache(endpoint_key, endpoint_port)
    local endpoint_content = endpoint_dict:get_stale(endpoint_key)
    if not endpoint_content then
        core.log.error("get empty endpoint content from discovery DIC, this should not happen ",
                endpoint_key)
        return nil
    end

    local endpoint = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.error("decode endpoint content failed, this should not happen, content: ",
                endpoint_content)
        return nil
    end

    return endpoint[endpoint_port]
end

local _M = {
    version = "0.0.1"
}

function _M.nodes(service_name)
    local pattern = "^(.*):(.*)$"  -- namespace/name:port_name
    local match = ngx.re.match(service_name, pattern, "jo")
    if not match then
        core.log.info("get unexpected upstream service_name:　", service_name)
        return nil
    end

    local endpoint_key = match[1]
    local endpoint_port = match[2]
    local endpoint_version = endpoint_dict:get_stale(endpoint_key .. "#version")
    if not endpoint_version then
        core.log.info("get empty endpoint version from discovery DICT ", endpoint_key)
        return nil
    end

    return endpoint_lrucache(service_name, endpoint_version,
            create_endpoint_lrucache, endpoint_key, endpoint_port)
end


function _M.init_worker()
    endpoint_dict = ngx.shared.kubernetes
    if not endpoint_dict then
        error("failed to get lua_shared_dict: kubernetes, please check your APISIX version")
    end

    if process.type() ~= "privileged agent" then
        return
    end

    local discovery_conf = local_conf.discovery.kubernetes

    default_weight = discovery_conf.default_weight

    local apiserver, err = get_apiserver(discovery_conf)
    if err then
        error(err)
        return
    end

    local endpoints_informer, err = informer_factory.new("", "v1",
            "Endpoints", "endpoints", "")
    if err then
        error(err)
        return
    end

    setup_namespace_selector(discovery_conf, endpoints_informer)
    setup_label_selector(discovery_conf, endpoints_informer)

    endpoints_informer.on_added = on_endpoint_modified
    endpoints_informer.on_modified = on_endpoint_modified
    endpoints_informer.on_deleted = on_endpoint_deleted
    endpoints_informer.pre_list = pre_list
    endpoints_informer.post_list = post_list

    local timer_runner
    timer_runner = function(premature)
        if premature then
            return
        end

        local ok, status = pcall(endpoints_informer.list_watch, endpoints_informer, apiserver)

        local retry_interval = 0
        if not ok then
            core.log.error("list_watch failed, kind: ", endpoints_informer.kind,
                    ", reason: ", "RuntimeException", ", message : ", status)
            retry_interval = 40
        elseif not status then
            retry_interval = 40
        end

        ngx.timer.at(retry_interval, timer_runner)
    end

    ngx.timer.at(0, timer_runner)
end

return _M
