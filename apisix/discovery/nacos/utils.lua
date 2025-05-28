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

local str_format    = string.format
local OLD_CONFIG_ID = "0"
local default_namespace_id = "public"
local default_group_name = "DEFAULT_GROUP"
local _M = {
  old_config_id = OLD_CONFIG_ID,
  default_namespace_id = default_namespace_id,
  default_group_name = default_group_name,
}

local function parse_service_name(service_name)
    -- support old data
    -- NOTE: If old service_name contains "/", it will be parsed as
    -- registry_id/namespace_id/group_name/service_name
    -- and termed invalid
    if not service_name:find("/") then
         return OLD_CONFIG_ID, "", "",  service_name
    end
    local pattern = "^(.*)/(.*)/(.*)/(.*)$" -- registry_id/namespace_id/group_name/service_name
    local match = ngx.re.match(service_name, pattern, "jo")
    if not match then
        core.log.error("get unexpected upstream service_name: ", service_name)
        return ""
    end

    return match[1], match[2], match[3], match[4]
end

_M.parse_service_name = parse_service_name

local function de_duplication(services, namespace_id, group_name, service_name, scheme)
    for _, service in ipairs(services) do
        if service.namespace_id == namespace_id and service.group_name == group_name
                and service.service_name == service_name and service.scheme == scheme then
            return true
        end
    end
    return false
end

local function iter_and_add_service(services, hash, id, values)
    if not values then
        return
    end

    for _, value in core.config_util.iterate_values(values) do
        local conf = value.value
        if not conf then
            goto CONTINUE
        end

        local upstream
        if conf.upstream then
            upstream = conf.upstream
        else
            upstream = conf
        end

        if upstream.discovery_type ~= "nacos" then
            goto CONTINUE
        end

        if hash[upstream.service_name] then
            goto CONTINUE
        end

        local service_registry_id, namespace_id,
              group_name, name = parse_service_name(upstream.service_name)
        if service_registry_id ~= id then
            goto CONTINUE
        end

        if not namespace_id or namespace_id == "" then
            namespace_id = upstream.discovery_args and upstream.discovery_args.namespace_id
                           or default_namespace_id
        end
        if not group_name or group_name == "" then
            group_name = upstream.discovery_args and upstream.discovery_args.group_name
                         or default_group_name
        end
        local dup = de_duplication(services, namespace_id, group_name,
        upstream.service_name, upstream.scheme)
        if dup then
            goto CONTINUE
        end
        core.table.insert(services, {
            name = name,
            namespace_id = namespace_id,
            group_name = group_name,
            service_name = upstream.service_name,
            id = id,
        })

        ::CONTINUE::
    end
end

function _M.generate_key(id, ns_id, group_name, service_name)
    -- new data expects service_name to be in the format and
    -- will use that as key directly

    if service_name:find("/") then
        return service_name
   end
    return str_format("%s/%s/%s/%s", id, ns_id, group_name, service_name)
end

function _M.get_nacos_services(service_registry_id)
    local services = {}
    local services_hash = {}

    -- here we use lazy load to work around circle dependency
    local get_upstreams = require('apisix.upstream').upstreams
    local get_routes = require('apisix.router').http_routes
    local get_stream_routes = require('apisix.router').stream_routes
    local get_services = require('apisix.http.service').services
    local values = get_upstreams()
    iter_and_add_service(services, services_hash, service_registry_id, values)
    values = get_routes()
    iter_and_add_service(services, services_hash, service_registry_id, values)
    values = get_services()
    iter_and_add_service(services, services_hash, service_registry_id, values)
    values = get_stream_routes()
    iter_and_add_service(services, services_hash, service_registry_id, values)
    return services
end


function _M.generate_signature(group_name, service_name, access_key, secret_key)
    local str_to_sign = ngx.now() * 1000 .. '@@' .. group_name .. '@@' .. service_name
    return access_key, str_to_sign, ngx.encode_base64(ngx.hmac_sha1(secret_key, str_to_sign))
end


function _M.generate_request_params(params)
    if params == nil then
        return ""
    end

    local args = ""
    local first = false
    for k, v in pairs(params) do
        if not first then
            args = str_format("%s&%s=%s", args, k, v)
        else
            first = true
            args = str_format("%s=%s", k, v)
        end
    end

    return args
end


function _M.match_metdata(node_metadata, upstream_metadata)
    if upstream_metadata == nil then
        return true
    end

    if not node_metadata then
        node_metadata = {}
    end

    for k, v in pairs(upstream_metadata) do
        if not node_metadata[k] or node_metadata[k] ~= v then
            return false
        end
    end

    return true
end


return _M
