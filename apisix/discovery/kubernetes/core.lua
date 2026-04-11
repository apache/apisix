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

--- Reusable building blocks for Kubernetes service discovery.
--- Extracted from init.lua so that both static-config mode and
--- dynamic-config mode can share the same core logic.

local ngx          = ngx
local ipairs        = ipairs
local pairs         = pairs
local type          = type
local unpack        = unpack
local string        = string
local tonumber      = tonumber
local tostring      = tostring
local os            = os
local pcall         = pcall
local setmetatable  = setmetatable

local core = require("apisix.core")
local util = require("apisix.cli.util")
local default_informer_factory = require("apisix.discovery.kubernetes.informer_factory")


local _M = {}

local endpoint_buffer = {}
local kubernetes_service_name_label = "kubernetes.io/service-name"


-- ─── helpers ──────────────────────────────────────────────────────────

local function sort_nodes_cmp(left, right)
    if left.host ~= right.host then
        return left.host < right.host
    end
    return left.port < right.port
end


local function build_endpoint_key(key_prefix, namespace, name)
    if key_prefix and key_prefix ~= "" then
        return key_prefix .. "/" .. namespace .. "/" .. name
    end
    return namespace .. "/" .. name
end


-- ─── config parsing (exported) ────────────────────────────────────────

function _M.read_env(key)
    if #key > 3 then
        local first, second = string.byte(key, 1, 2)
        if first == string.byte('$') and second == string.byte('{') then
            local last = string.byte(key, #key)
            if last == string.byte('}') then
                local env = string.sub(key, 3, #key - 1)
                local value = os.getenv(env)
                if not value then
                    return nil, "not found environment variable " .. env
                end
                return value
            end
        end
    end
    return key
end


function _M.read_token(token_file)
    local token, err = util.read_file(token_file)
    if err then
        return nil, err
    end
    return util.trim(token)
end


function _M.get_apiserver(conf)
    local apiserver = {
        schema = "",
        host   = "",
        port   = "",
    }

    apiserver.schema = conf.service.schema
    if apiserver.schema ~= "http" and apiserver.schema ~= "https" then
        return nil, "service.schema should set to one of [http,https] but " .. apiserver.schema
    end

    local err
    apiserver.host, err = _M.read_env(conf.service.host)
    if err then
        return nil, err
    end
    if apiserver.host == "" then
        return nil, "service.host should set to non-empty string"
    end

    local port
    port, err = _M.read_env(conf.service.port)
    if err then
        return nil, err
    end
    apiserver.port = tonumber(port)
    if not apiserver.port or apiserver.port <= 0 or apiserver.port > 65535 then
        return nil, "invalid port value: " .. (apiserver.port or "nil")
    end

    if conf.client.token then
        local token
        token, err = _M.read_env(conf.client.token)
        if err then
            return nil, err
        end
        apiserver.token = util.trim(token)
    elseif conf.client.token_file and conf.client.token_file ~= "" then
        setmetatable(apiserver, {
            __index = function(_, key)
                if key ~= "token" then
                    return
                end
                local token_file
                token_file, err = _M.read_env(conf.client.token_file)
                if err then
                    core.log.error("failed to read token file path: ", err)
                    return
                end
                local token
                token, err = _M.read_token(token_file)
                if err then
                    core.log.error("failed to read token from file: ", err)
                    return
                end
                core.log.debug("re-read the token value")
                return token
            end
        })
    else
        return nil, "one of [client.token,client.token_file] should be set but none"
    end

    if apiserver.schema == "https" and apiserver.token == "" then
        return nil, "apiserver.token should set to non-empty string when service.schema is https"
    end

    -- ssl_verify: use explicit config if set, otherwise default to false
    if conf.service.ssl_verify ~= nil then
        apiserver.ssl_verify = conf.service.ssl_verify
    else
        apiserver.ssl_verify = false
    end

    return apiserver
end


function _M.setup_namespace_selector(conf, informer)
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
                m, err = ngx.re.match(namespace, v, "jo")
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


function _M.setup_label_selector(conf, informer)
    informer.label_selector = conf.label_selector
end


-- ─── endpoint dict operations (exported) ──────────────────────────────

function _M.update_endpoint_dict(handle, endpoints, endpoint_key)
    local endpoint_content = core.json.encode(endpoints, true)
    local endpoint_version = ngx.crc32_long(endpoint_content)
    local _, err
    _, err = handle.endpoint_dict:safe_set(endpoint_key .. "#version", endpoint_version)
    if err then
        return false, "set endpoint version into discovery DICT failed, " .. err
    end
    _, err = handle.endpoint_dict:safe_set(endpoint_key, endpoint_content)
    if err then
        handle.endpoint_dict:delete(endpoint_key .. "#version")
        return false, "set endpoint into discovery DICT failed, " .. err
    end
    return true
end


function _M.create_endpoint_lrucache(endpoint_dict, endpoint_key, endpoint_port)
    local endpoint_content = endpoint_dict:get(endpoint_key)
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


-- ─── endpoint callback factory ────────────────────────────────────────
--- Create a set of informer callbacks parameterized by options.
---
--- options:
---   key_prefix           (string|nil) prefix for endpoint dict keys, used for
---                         multi-registry isolation on a shared dict.
---   duplicate_port_number (bool|nil)  when true, store nodes under the numeric
---                         port key in addition to the port name key.
---
--- Returns a table: {
---   on_endpoint_modified, on_endpoint_deleted,
---   on_endpoint_slices_modified, on_endpoint_slices_deleted,
---   pre_list, post_list
--- }

function _M.create_endpoint_callbacks(options)
    options = options or {}
    local key_prefix = options.key_prefix
    local dup_port = options.duplicate_port_number

    -- ── EndpointSlice helpers ──

    local function update_endpoint_slices_cache(handle, endpoint_key, slice, slice_name)
        if not handle.endpoint_slices_cache[endpoint_key] then
            handle.endpoint_slices_cache[endpoint_key] = {}
        end
        handle.endpoint_slices_cache[endpoint_key][slice_name] = slice
    end

    local function get_endpoints_from_cache(handle, endpoint_key)
        local endpoint_slices = handle.endpoint_slices_cache[endpoint_key] or {}
        local endpoints = {}
        for _, endpoint_slice in pairs(endpoint_slices) do
            for port, targets in pairs(endpoint_slice) do
                if not endpoints[port] then
                    endpoints[port] = core.table.new(0, #targets)
                end
                core.table.insert_tail(endpoints[port], unpack(targets))
            end
        end
        return endpoints
    end

    local function validate_endpoint_slice(endpoint_slice)
        if not endpoint_slice.metadata then
            return false, "endpoint_slice has no metadata, endpointSlice: "
                    .. core.json.encode(endpoint_slice)
        end
        if not endpoint_slice.metadata.name then
            return false, "endpoint_slice has no metadata.name, endpointSlice: "
                    .. core.json.encode(endpoint_slice)
        end
        if not endpoint_slice.metadata.namespace then
            return false, "endpoint_slice has no metadata.namespace, endpointSlice: "
                    .. core.json.encode(endpoint_slice)
        end
        if not endpoint_slice.metadata.labels
                or not endpoint_slice.metadata.labels[kubernetes_service_name_label] then
            return false, "endpoint_slice has no service-name, endpointSlice: "
                    .. core.json.encode(endpoint_slice)
        end
        return true
    end

    -- ── callbacks ──

    local function on_endpoint_slices_modified(handle, endpoint_slice, operate)
        local ok, err = validate_endpoint_slice(endpoint_slice)
        if not ok then
            core.log.error("endpoint_slice validation fail: ", err)
            return
        end
        if handle.namespace_selector and
                not handle:namespace_selector(endpoint_slice.metadata.namespace) then
            return
        end

        core.log.debug("get endpoint_slice: ", core.json.delay_encode(endpoint_slice))
        local port_to_nodes = {}

        local slice_endpoints = endpoint_slice.endpoints
        if not slice_endpoints or slice_endpoints == ngx.null then
            slice_endpoints = {}
        end

        for _, ep in ipairs(slice_endpoints) do
            if ep.addresses and ep.conditions and ep.conditions.ready then
                local addresses = ep.addresses
                for _, port in ipairs(endpoint_slice.ports or {}) do
                    local port_name
                    if port.name then
                        port_name = port.name
                    elseif port.targetPort then
                        port_name = tostring(port.targetPort)
                    else
                        port_name = tostring(port.port)
                    end

                    local nodes = port_to_nodes[port_name]
                    if nodes == nil then
                        nodes = core.table.new(0, #slice_endpoints * #addresses)
                        port_to_nodes[port_name] = nodes
                    end

                    for _, ip in ipairs(addresses) do
                        core.table.insert(nodes, {
                            host = ip,
                            port = port.port,
                            weight = handle.default_weight
                        })
                    end

                    if dup_port and port.name then
                        port_to_nodes[tostring(port.port)] = core.table.deepcopy(nodes)
                    end
                end
            end
        end

        local svc_name = endpoint_slice.metadata.labels[kubernetes_service_name_label]
        local endpoint_key = build_endpoint_key(
            key_prefix, endpoint_slice.metadata.namespace, svc_name)
        update_endpoint_slices_cache(
            handle, endpoint_key, port_to_nodes, endpoint_slice.metadata.name)

        local cached_endpoints = get_endpoints_from_cache(handle, endpoint_key)
        for _, nodes in pairs(cached_endpoints) do
            core.table.sort(nodes, sort_nodes_cmp)
        end

        ok, err = _M.update_endpoint_dict(handle, cached_endpoints, endpoint_key)
        if not ok then
            core.log.error("failed to update endpoint dict for endpoint: ", endpoint_key,
                    ", err: ", err)
            return
        end
        if operate == "list" then
            handle.current_keys_hash[endpoint_key] = true
            handle.current_keys_hash[endpoint_key .. "#version"] = true
        end
    end

    local function on_endpoint_slices_deleted(handle, endpoint_slice)
        local ok, err = validate_endpoint_slice(endpoint_slice)
        if not ok then
            core.log.error("endpoint_slice validation fail: ", err)
            return
        end
        if handle.namespace_selector and
                not handle:namespace_selector(endpoint_slice.metadata.namespace) then
            return
        end

        core.log.debug("delete endpoint_slice: ", core.json.delay_encode(endpoint_slice))

        local svc_name = endpoint_slice.metadata.labels[kubernetes_service_name_label]
        local endpoint_key = build_endpoint_key(
            key_prefix, endpoint_slice.metadata.namespace, svc_name)
        update_endpoint_slices_cache(handle, endpoint_key, nil, endpoint_slice.metadata.name)

        local cached_endpoints = get_endpoints_from_cache(handle, endpoint_key)
        for _, nodes in pairs(cached_endpoints) do
            core.table.sort(nodes, sort_nodes_cmp)
        end

        ok, err = _M.update_endpoint_dict(handle, cached_endpoints, endpoint_key)
        if not ok then
            core.log.error("failed to update endpoint dict for endpoint: ", endpoint_key,
                    ", err: ", err)
        end
    end

    local function on_endpoint_modified(handle, endpoint, operate)
        if handle.namespace_selector and
                not handle:namespace_selector(endpoint.metadata.namespace) then
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
                            weight = handle.default_weight
                        })
                    end

                    if dup_port and port.name then
                        endpoint_buffer[tostring(port.port)] = core.table.deepcopy(nodes)
                    end
                end
            end
        end

        for _, nodes in pairs(endpoint_buffer) do
            core.table.sort(nodes, sort_nodes_cmp)
        end

        local endpoint_key = build_endpoint_key(
            key_prefix, endpoint.metadata.namespace, endpoint.metadata.name)
        local ok, err = _M.update_endpoint_dict(handle, endpoint_buffer, endpoint_key)
        if not ok then
            core.log.error("failed to update endpoint dict for endpoint: ", endpoint_key,
                    ", err: ", err)
            return
        end
        if operate == "list" then
            handle.current_keys_hash[endpoint_key] = true
            handle.current_keys_hash[endpoint_key .. "#version"] = true
        end
    end

    local function on_endpoint_deleted(handle, endpoint)
        if handle.namespace_selector and
                not handle:namespace_selector(endpoint.metadata.namespace) then
            return
        end

        core.log.debug(core.json.delay_encode(endpoint))
        local endpoint_key = build_endpoint_key(
            key_prefix, endpoint.metadata.namespace, endpoint.metadata.name)
        handle.endpoint_dict:delete(endpoint_key .. "#version")
        handle.endpoint_dict:delete(endpoint_key)
    end

    -- pre_list / post_list are prefix-aware: when key_prefix is set,
    -- only keys belonging to this prefix are considered for dirty-data cleanup.
    local function pre_list(handle)
        handle.current_keys_hash = {}
        local all_keys = handle.endpoint_dict:get_keys(0)
        if key_prefix and key_prefix ~= "" then
            handle.existing_keys = {}
            local prefix = key_prefix .. "/"
            for _, key in ipairs(all_keys) do
                if core.string.has_prefix(key, prefix)
                        or key == "discovery_ready:" .. key_prefix then
                    core.table.insert(handle.existing_keys, key)
                end
            end
        else
            handle.existing_keys = all_keys
        end
        if handle.endpoint_slices_cache then
            handle.endpoint_slices_cache = {}
        end
    end

    local function post_list(handle)
        if handle.existing_keys and handle.current_keys_hash then
            for _, key in ipairs(handle.existing_keys) do
                if not handle.current_keys_hash[key] then
                    core.log.info("kubernetes discovery module found dirty data in shared dict, ",
                                  "key: ", key)
                    handle.endpoint_dict:delete(key)
                end
            end
            handle.existing_keys = nil
            handle.current_keys_hash = nil
        end
        local ready_key = (key_prefix and key_prefix ~= "")
            and ("discovery_ready:" .. key_prefix)
            or "discovery_ready"
        local _, err = handle.endpoint_dict:safe_set(ready_key, true)
        if err then
            core.log.error("set discovery_ready flag into discovery DICT failed, ", err)
        end
    end

    return {
        on_endpoint_modified        = on_endpoint_modified,
        on_endpoint_deleted         = on_endpoint_deleted,
        on_endpoint_slices_modified = on_endpoint_slices_modified,
        on_endpoint_slices_deleted  = on_endpoint_slices_deleted,
        pre_list                    = pre_list,
        post_list                   = post_list,
    }
end


-- ─── handle factory ───────────────────────────────────────────────────
--- Create a fully configured Kubernetes discovery handle.
---
--- conf: standard kubernetes discovery config (service, client,
---       namespace_selector, label_selector, default_weight,
---       watch_endpoint_slices)
---
--- options:
---   endpoint_dict         (ngx.shared.DICT)  required — the shared dict to use
---   key_prefix            (string|nil)        prefix for endpoint keys
---   duplicate_port_number (bool|nil)          store nodes under numeric port too
---   informer_factory      (table|nil)         custom informer factory module

function _M.create_handle(conf, options)
    local endpoint_dict = options.endpoint_dict
    if not endpoint_dict then
        return nil, "endpoint_dict is required"
    end

    local apiserver, err = _M.get_apiserver(conf)
    if err then
        return nil, err
    end

    local default_weight = conf.default_weight or 50

    local inf_factory = options.informer_factory or default_informer_factory
    local endpoints_informer
    if conf.watch_endpoint_slices then
        endpoints_informer, err = inf_factory.new(
            "discovery.k8s.io", "v1", "EndpointSlice", "endpointslices", "")
    else
        endpoints_informer, err = inf_factory.new("", "v1", "Endpoints", "endpoints", "")
    end
    if err then
        return nil, err
    end

    _M.setup_namespace_selector(conf, endpoints_informer)
    _M.setup_label_selector(conf, endpoints_informer)

    local cbs = _M.create_endpoint_callbacks({
        key_prefix            = options.key_prefix,
        duplicate_port_number = options.duplicate_port_number,
    })

    if conf.watch_endpoint_slices then
        endpoints_informer.on_added    = cbs.on_endpoint_slices_modified
        endpoints_informer.on_modified = cbs.on_endpoint_slices_modified
        endpoints_informer.on_deleted  = cbs.on_endpoint_slices_deleted
        endpoints_informer.endpoint_slices_cache = {}
    else
        endpoints_informer.on_added    = cbs.on_endpoint_modified
        endpoints_informer.on_modified = cbs.on_endpoint_modified
        endpoints_informer.on_deleted  = cbs.on_endpoint_deleted
    end

    endpoints_informer.pre_list  = cbs.pre_list
    endpoints_informer.post_list = cbs.post_list

    local handle = setmetatable({
        endpoint_dict  = endpoint_dict,
        apiserver      = apiserver,
        default_weight = default_weight,
    }, { __index = endpoints_informer })

    return handle
end


-- ─── lifecycle ────────────────────────────────────────────────────────

function _M.start_fetch(handle)
    local timer_runner
    timer_runner = function(premature)
        if premature then
            return
        end
        if handle.stop then
            core.log.info("stop fetching, kind: ", handle.kind)
            return
        end

        local ok, status = pcall(handle.list_watch, handle, handle.apiserver)

        local retry_interval = 0
        if not ok then
            core.log.error("list_watch failed, kind: ", handle.kind,
                    ", reason: ", "RuntimeException", ", message : ", status)
            retry_interval = 40
        elseif not status then
            retry_interval = 40
        end

        if not handle.stop then
            ngx.timer.at(retry_interval, timer_runner)
        end
    end
    ngx.timer.at(0, timer_runner)
end


-- ─── node resolution ──────────────────────────────────────────────────
--- Resolve service_name to upstream nodes from a shared dict with LRU cache.
---
--- endpoint_lrucache: core.lrucache instance
--- service_name: the full service name (e.g. "ns/svc:port" or "id/ns/svc:port")
--- pattern: regex to parse service_name; must capture (endpoint_key_group, port)
---          where endpoint_key_group is used as-is for dict lookup
--- dict_resolver: function(match) → endpoint_dict, endpoint_key
---                returns the dict and the key to look up

function _M.resolve_nodes(endpoint_lrucache, service_name, pattern, dict_resolver)
    local match = ngx.re.match(service_name, pattern, "jo")
    if not match then
        core.log.error("get unexpected upstream service_name: ", service_name)
        return nil
    end

    local endpoint_dict, endpoint_key, endpoint_port = dict_resolver(match)
    if not endpoint_dict then
        core.log.error("failed to resolve endpoint dict for service: ", service_name)
        return nil
    end

    local endpoint_version = endpoint_dict:get(endpoint_key .. "#version")
    if not endpoint_version then
        core.log.info("get empty endpoint version from discovery DICT ", endpoint_key)
        return nil
    end

    return endpoint_lrucache(service_name, endpoint_version,
            _M.create_endpoint_lrucache, endpoint_dict, endpoint_key, endpoint_port)
end


-- ─── dict helpers ─────────────────────────────────────────────────────

function _M.dump_endpoints_from_dict(endpoint_dict)
    local keys, err = endpoint_dict:get_keys(0)
    if err then
        core.log.error("get keys from discovery dict failed: ", err)
        return
    end

    if not keys or #keys == 0 then
        return
    end

    local endpoints = {}
    for i = 1, #keys do
        local key = keys[i]
        if key:sub(-#"#version") ~= "#version"
                and not core.string.has_prefix(key, "discovery_ready") then
            local value = endpoint_dict:get(key)
            core.table.insert(endpoints, {
                name = key,
                value = value
            })
        end
    end

    return endpoints
end


return _M
