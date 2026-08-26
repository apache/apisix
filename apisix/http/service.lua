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
local core   = require("apisix.core")
local config_local = require("apisix.core.config_local")
local apisix_upstream = require("apisix.upstream")
local plugin_checker = require("apisix.plugin").plugin_checker
local plugin = require("apisix.plugin")
local check_schema = require("apisix.core.schema").check
local services
local error = error
local ipairs = ipairs
local type = type
local str_lower = string.lower
local str_sub = string.sub
local is_graphql_cost_decoration_key


local _M = {
    version = 0.2,
}


function _M.get(service_id)
    return services:get(service_id)
end


function _M.services()
    if not services then
        return nil, nil
    end

    return services.values, services.conf_version
end


local function filter(service)
    service.has_domain = false
    if not service.value or is_graphql_cost_decoration_key(service.key) then
        return
    end

    -- normalize the hosts like `apisix/router.lua` does for routes: hostnames are
    -- case-insensitive, and they are matched against $host, which is always lowercase
    if service.value.hosts then
        for i, v in ipairs(service.value.hosts) do
            service.value.hosts[i] = str_lower(v)
        end
    end

    plugin.set_plugins_meta_parent(service.value.plugins, service)

    apisix_upstream.filter_upstream(service.value.upstream, service)

    core.log.info("filter service: ", core.json.delay_encode(service, true))
end


local function remove_etcd_prefix(key)
    local prefix = ""
    local local_conf = config_local.local_conf()
    local role = core.table.try_read_attr(local_conf, "deployment", "role")
    local provider = core.table.try_read_attr(local_conf, "deployment", "role_" ..
                        role, "config_provider")
    if provider == "etcd" and local_conf.etcd and local_conf.etcd.prefix then
        prefix = local_conf.etcd.prefix
    end
    return str_sub(key, #prefix + 1)
end


-- /{etcd.prefix}/services/{service_id}/graphql_cost_decorations/{decoration_id}
-- The graphql cost decorations are a sub resource of the service, exactly like
-- consumer credentials, so they arrive through this same watcher and have to be
-- told apart from the services themselves.
function is_graphql_cost_decoration_key(key)
    if not key then
        return false
    end

    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[2] == "services" and uri_segs[4] == "graphql_cost_decorations"
end
_M.is_graphql_cost_decoration_key = is_graphql_cost_decoration_key


-- services etcd range responses include the sub resources, so the admin list has
-- to drop them; mirrors apisix.consumer.filter_consumers_list.
function _M.filter_services_list(data_list)
    if not data_list or #data_list == 0 then
        return data_list or {}
    end

    local list = {}
    for _, item in ipairs(data_list) do
        if not (type(item) == "table" and is_graphql_cost_decoration_key(item.key)) then
            core.table.insert(list, item)
        end
    end

    return list
end


-- The watcher carries two kinds of item, so the schema cannot be declared with
-- item_schema; it is selected here by key, the way apisix.consumer does.
local function service_checker(...)
    local args = {...}
    local item, key = args[1], args[2]

    if is_graphql_cost_decoration_key(key) then
        return check_schema(core.schema.graphql_cost_decoration, item)
    end

    local data_valid, err = check_schema(core.schema.service, item)
    if not data_valid then
        return data_valid, err
    end

    return plugin_checker(...)
end


function _M.init_worker()
    local err
    services, err = core.config.new("/services", {
        automatic = true,
        checker = service_checker,
        filter = filter,
    })
    if not services then
        error("failed to create etcd instance for fetching /services: " .. err)
        return
    end
end


return _M
