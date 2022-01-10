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
local math = math
local os = os
local error = error
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local local_conf = require("apisix.core.config_local").local_conf()
local http = require("resty.http")
local endpoints_shared = ngx.shared.discovery

local AddedEven = "ADDED"
local ModifiedEvent = "MODIFIED"
local DeletedEvent = "DELETED"
local BookmarkEvent = "BOOKMARK"

local ListDrive = "list"
local WatchDrive = "watch"

local apiserver_schema = ""
local apiserver_host = ""
local apiserver_port = 0
local apiserver_token = ""
local default_weight = 0

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local endpoint_buffer = {}
local empty_table = {}

local function sort_cmp(left, right)
    if left.ip ~= right.ip then
        return left.ip < right.ip
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
    _, err = endpoints_shared:safe_set(endpoint_key .. "#version", endpoint_version)
    if err then
        core.log.emerg("set endpoint version into discovery DICT failed, ", err)
        return
    end
    endpoints_shared:safe_set(endpoint_key, endpoint_content)
    if err then
        core.log.emerg("set endpoint into discovery DICT failed, ", err)
        endpoints_shared:delete(endpoint_key .. "#version")
    end
end

local function on_endpoint_deleted(endpoint)
    core.log.debug(core.json.encode(endpoint, true))
    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    endpoints_shared:delete(endpoint_key .. "#version")
    endpoints_shared:delete(endpoint_key)
end

local function create_resource(group, version, kind, plural, namespace)
    local _t = {
        kind = kind,
        list_kind = kind .. "List",
        plural = plural,
        path = "",
        version = "",
        continue = "",
        overtime = "1800",
        limit = 30,
        label_selector = "",
        field_selector = "",
    }

    if group == "" then
        _t.path = _t.path .. "/api/" .. version
    else
        _t.path = _t.path .. "/apis/" .. group .. "/" .. version
    end

    if namespace ~= "" then
        _t.path = _t.path .. "/namespace/" .. namespace
    end
    _t.path = _t.path .. "/" .. plural

    function _t.list_query(self)
        local uri = "limit=" .. self.limit

        if self.continue ~= nil and self.continue ~= "" then
            uri = uri .. "&continue=" .. self.continue
        end

        if self.label_selector and self.label_selector ~= "" then
            uri = uri .. "&labelSelector=" .. self.label_selector
        end

        if self.field_selector and self.field_selector ~= "" then
            uri = uri .. "&filedSelector=" .. self.field_selector
        end

        return uri
    end

    function _t.watch_query(self)
        local uri = "watch=true&allowWatchBookmarks=true&timeoutSeconds=" .. self.overtime

        if self.version ~= nil and self.version ~= "" then
            uri = uri .. "&resourceVersion=" .. self.version
        end

        if self.label_selector and self.label_selector ~= "" then
            uri = uri .. "&labelSelector=" .. self.label_selector
        end

        if self.field_selector and self.field_selector ~= "" then
            uri = uri .. "&filedSelector=" .. self.field_selector
        end

        return uri
    end

    return _t
end

local function list_resource(httpc, resource)
    local res, err = httpc:request({
        path = resource.path,
        query = resource:list_query(),
        headers = {
            ["Host"] = apiserver_host .. ":" .. apiserver_port,
            ["Authorization"] = "Bearer " .. apiserver_token,
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    core.log.info("--raw=" .. resource.path .. "?" .. resource:list_query())

    if not res then
        return false, "RequestError", err or ""
    end

    if res.status ~= 200 then
        return false, res.reason, res:read_body() or ""
    end
    local body, err = res:read_body()
    if err then
        return false, "ReadBodyError", err
    end

    local data, _ = core.json.decode(body)
    if not data or data.kind ~= resource.list_kind then
        return false, "UnexpectedBody", body
    end

    resource.version = data.metadata.resourceVersion

    if resource.on_added ~= nil then
        for _, item in ipairs(data.items or empty_table) do
            resource:on_added(item, ListDrive)
        end
    end

    resource.continue = data.metadata.continue
    if data.metadata.continue ~= nil and data.metadata.continue ~= "" then
        list_resource(httpc, resource)
    end

    return true, "Success", ""
end

local function watch_resource(httpc, resource)
    local watch_seconds = 1800 + math.random(9, 999)
    resource.overtime = watch_seconds
    local http_seconds = watch_seconds + 120
    httpc:set_timeouts(2000, 3000, http_seconds * 1000)
    local res, err = httpc:request({
        path = resource.path,
        query = resource:watch_query(),
        headers = {
            ["Host"] = apiserver_host .. ":" .. apiserver_port,
            ["Authorization"] = "Bearer " .. apiserver_token,
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    core.log.info("--raw=" .. resource.path .. "?" .. resource:watch_query())

    if err then
        return false, "RequestError", err
    end

    if res.status ~= 200 then
        return false, res.reason, res:read_body() or ""
    end

    local remainder_body = ""
    local body
    local reader = res.body_reader
    local gmatch_iterator
    local captures
    local captured_size = 0
    while true do

        body, err = reader()
        if err then
            return false, "ReadBodyError", err
        end

        if not body then
            break
        end

        if #remainder_body ~= 0 then
            body = remainder_body .. body
        end

        gmatch_iterator, err = ngx.re.gmatch(body, "{\"type\":.*}\n", "jao")
        if not gmatch_iterator then
            return false, "GmatchError", err
        end

        while true do
            captures, err = gmatch_iterator()
            if err then
                return false, "GmatchError", err
            end
            if not captures then
                break
            end
            captured_size = captured_size + #captures[0]
            local v, _ = core.json.decode(captures[0])
            if not v or not v.object or v.object.kind ~= resource.kind then
                return false, "UnexpectedBody", captures[0]
            end

            resource.version = v.object.metadata.resourceVersion
            local type = v.type
            if type == AddedEven then
                if resource.on_added ~= nil then
                    resource:on_added(v.object, WatchDrive)
                end
            elseif type == DeletedEvent then
                if resource.on_deleted ~= nil then
                    resource:on_deleted(v.object)
                end
            elseif type == ModifiedEvent then
                if resource.on_modified ~= nil then
                    resource:on_modified(v.object)
                end
            elseif type == BookmarkEvent then
                --    do nothing
            end
        end

        if captured_size == #body then
            remainder_body = ""
        elseif captured_size == 0 then
            remainder_body = body
        else
            remainder_body = string.sub(body, captured_size + 1)
        end
    end
    watch_resource(httpc, resource)
end

local function fetch_resource(resource)
    while true do
        local ok
        local reason, message
        local retry_interval
        repeat
            local httpc = http.new()
            resource.fetch_state = "connecting"
            core.log.info("begin to connect ", apiserver_host, ":", apiserver_port)
            ok, message = httpc:connect({
                scheme = apiserver_schema,
                host = apiserver_host,
                port = apiserver_port,
                ssl_verify = false
            })
            if not ok then
                resource.fetch_state = "connecting"
                core.log.error("connect apiserver failed , apiserver_host: ", apiserver_host,
                        ", apiserver_port", apiserver_port, ", message : ", message)
                retry_interval = 100
                break
            end

            core.log.info("begin to list ", resource.plural)
            resource.fetch_state = "listing"
            if resource.pre_List ~= nil then
                resource:pre_list()
            end
            ok, reason, message = list_resource(httpc, resource)
            if not ok then
                resource.fetch_state = "list failed"
                core.log.error("list failed, resource: ", resource.plural,
                        ", reason: ", reason, ", message : ", message)
                retry_interval = 100
                break
            end
            resource.fetch_state = "list finished"
            if resource.post_List ~= nil then
                resource:post_list()
            end

            core.log.info("begin to watch ", resource.plural)
            resource.fetch_state = "watching"
            ok, reason, message = watch_resource(httpc, resource)
            if not ok then
                resource.fetch_state = "watch failed"
                core.log.error("watch failed, resource: ", resource.plural,
                        ", reason: ", reason, ", message : ", message)
                retry_interval = 0
                break
            end
            resource.fetch_state = "watch finished"
            retry_interval = 0
        until true
    end
end

local function set_namespace_selector(conf, resource)
    local ns = conf.namespace_selector
    if ns == nil then
        resource.namespace_filter = function(self, namespace)
            return true
        end
    elseif ns.equal then
        resource.field_selector = "metadata.namespace%3D" .. ns.equal
        resource.namespace_filter = function(self, namespace)
            return true
        end
    elseif ns.not_equal then
        resource.field_selector = "metadata.namespace%21%3D" .. ns.not_equal
        resource.namespace_filter = function(self, namespace)
            return true
        end
    elseif ns.match then
        resource.namespace_filter = function(self, namespace)
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
        resource.namespace_filter = function(self, namespace)
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

local function read_conf(conf)
    apiserver_schema = conf.service.schema

    local ok, value, message
    ok, value, message = read_env(conf.service.host)
    if not ok then
        return false, message
    end
    apiserver_host = value
    if apiserver_host == "" then
        return false, "get empty host value"
    end

    ok, value, message = read_env(conf.service.port)
    if not ok then
        return false, message
    end
    apiserver_port = tonumber(value)
    if not apiserver_port or apiserver_port <= 0 or apiserver_port > 65535 then
        return false, "get invalid port value: " .. apiserver_port
    end

    -- we should not check if the apiserver_token is empty here
    if conf.client.token then
        ok, value, message = read_env(conf.client.token)
        if not ok then
            return false, message
        end
        apiserver_token = value
    elseif conf.client.token_file and conf.client.token_file ~= "" then
        ok, value, message = read_env(conf.client.token_file)
        if not ok then
            return false, message
        end
        local apiserver_token_file = value

        apiserver_token, message = util.read_file(apiserver_token_file)
        if not apiserver_token then
            return false, message
        end
    else
        return false, "invalid k8s discovery configuration:" ..
                "should set one of [client.token,client.token_file] but none"
    end

    default_weight = conf.default_weight or 50

    return true, nil
end

local function create_endpoint_lrucache(endpoint_key, endpoint_port)
    local endpoint_content, _, _ = endpoints_shared:get_stale(endpoint_key)
    if not endpoint_content then
        core.log.emerg("get empty endpoint content from discovery DIC, this should not happen ",
                endpoint_key)
        return nil
    end

    local endpoint, _ = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.emerg("decode endpoint content failed, this should not happen, content : ",
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
    local endpoint_version, _, _ = endpoints_shared:get_stale(endpoint_key .. "#version")
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

    local ok, err = read_conf(local_conf.discovery.k8s)
    if not ok then
        error(err)
        return
    end

    local resource = create_resource("", "v1", "Endpoints", "endpoints", "")

    set_namespace_selector(local_conf.discovery.k8s, resource)

    resource.on_added = function(self, object, drive)
        if self.namespace_selector ~= nil then
            if self:namespace_selector(object.metadata.namespace) then
                on_endpoint_modified(object)
            end
        else
            on_endpoint_modified(object)
        end
    end

    resource.on_modified = resource.on_added

    resource.on_deleted = function(self, object)
        if self.namespace_selector ~= nil then
            if self:namespace_selector(object.metadata.namespace) then
                on_endpoint_deleted(object)
            end
        else
            on_endpoint_deleted(object)
        end
    end

    local timer_runner
    timer_runner = function()
        fetch_resource(resource)
        ngx.timer.at(0, timer_runner)
    end
    ngx.timer.at(0, timer_runner)
end

return _M
