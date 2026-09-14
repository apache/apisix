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
local config_util = require("apisix.core.config_util")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local get_plugin_configs = require("apisix.plugin_config").plugin_configs
local get_consumers = require("apisix.consumer").consumers
local get_consumer_groups = require("apisix.consumer_group").consumer_groups
local get_global_rules = require("apisix.global_rules").global_rules
local apisix_upstream = require("apisix.upstream")
local resource = require("apisix.admin.resource")
local tostring = tostring
local ipairs = ipairs
local type = type


local function list_resources(path)
    local res, err = core.etcd.get(path, true)
    if not res then
        return nil, {error_msg = "failed to fetch " .. path .. ": " .. err}
    end

    -- a prefix nothing has been written under yet is a 404, not an error
    if res.status == 404 then
        return {}
    end

    if res.status ~= 200 then
        return nil, {error_msg = "failed to fetch " .. path .. ", response code: "
                                 .. res.status}
    end

    local nodes = res.body.list
    if not nodes and res.body.node then
        nodes = res.body.node.nodes
    end

    local values = {}
    for _, item in ipairs(nodes or {}) do
        local value = item.value
        if type(value) == "string" then
            value = core.json.decode(value)
        end

        if type(value) == "table" then
            core.table.insert(values, value)
        end
    end

    return values
end


-- The stream subsystem never ramps node weights, so an upstream a stream route
-- can reach may not enable slow start: the configuration would be accepted and
-- then silently ignored on the L4 path. A route reaches one through its own
-- `upstream_id`, or - when it names none - through the service it uses, which is
-- the fallback `merge_service_stream_route` applies at runtime.
local function check_stream_route_reference(id, conf, opts)
    if not (conf.warm_up_conf and id) or opts.skip_references_check then
        return true
    end

    local routes, err = list_resources("/stream_routes")
    if not routes then
        return nil, err
    end

    local via_service = {}
    local has_service_ref = false
    for _, route in ipairs(routes) do
        if route.upstream_id and tostring(route.upstream_id) == tostring(id) then
            return nil, {error_msg = "can not enable warm_up_conf on this upstream, "
                                     .. "stream route [" .. tostring(route.id)
                                     .. "] is using it now"}
        end

        if route.service_id and not route.upstream_id then
            via_service[tostring(route.service_id)] = tostring(route.id)
            has_service_ref = true
        end
    end

    if not has_service_ref then
        return true
    end

    local services, err = list_resources("/services")
    if not services then
        return nil, err
    end

    for _, service in ipairs(services) do
        local route_id = via_service[tostring(service.id)]
        if route_id and service.upstream_id
           and tostring(service.upstream_id) == tostring(id) then

            return nil, {error_msg = "can not enable warm_up_conf on this upstream, "
                                     .. "stream route [" .. route_id .. "] is using it "
                                     .. "through service [" .. tostring(service.id)
                                     .. "] now"}
        end
    end

    return true
end


local function check_conf(id, conf, need_id, schema, opts)
    opts = opts or {}

    local ok, err = apisix_upstream.check_upstream_conf(conf)
    if not ok then
        return nil, {error_msg = err}
    end

    local ok, err = check_stream_route_reference(id, conf, opts)
    if not ok then
        return nil, err
    end

    return true
end


local function encrypt_conf(id, conf)
    apisix_upstream.encrypt_conf(conf)
end


local function up_id_in_plugins(plugins, up_id)
    if plugins and plugins["traffic-split"]
        and plugins["traffic-split"].rules then

        for _, rule in ipairs(plugins["traffic-split"].rules) do
            local plugin_upstreams = rule.weighted_upstreams
            for _, plugin_upstream in ipairs(plugin_upstreams) do
                if plugin_upstream.upstream_id
                    and tostring(plugin_upstream.upstream_id) == up_id then
                     return true
                end
            end
        end

        return false
    end
end


local function check_resources_reference(resources, up_id,
                                         only_check_plugin, resources_name)
    if resources then
        for _, resource in config_util.iterate_values(resources) do
            if resource and resource.value then
                if up_id_in_plugins(resource.value.plugins, up_id) then
                    return {error_msg = "can not delete this upstream,"
                                        .. " plugin in "
                                        .. resources_name .. " ["
                                        .. resource.value.id
                                        .. "] is still using it now"}
                end

                if not only_check_plugin and resource.value.upstream_id
                    and tostring(resource.value.upstream_id) == up_id then
                     return {error_msg = "can not delete this upstream, "
                                         .. resources_name .. " [" .. resource.value.id
                                         .. "] is still using it now"}
                end
            end
        end
    end
end


local function delete_checker(id)
    local routes = get_routes()
    local err_msg = check_resources_reference(routes, id, false, "route")
    if err_msg then
        return 400, err_msg
    end

    local services, services_ver = get_services()
    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)
    local err_msg = check_resources_reference(services, id, false, "service")
    if err_msg then
        return 400, err_msg
    end

    local plugin_configs = get_plugin_configs()
    local err_msg = check_resources_reference(plugin_configs, id, true, "plugin_config")
    if err_msg then
        return 400, err_msg
    end

    local consumers = get_consumers()
    local err_msg = check_resources_reference(consumers, id, true, "consumer")
    if err_msg then
        return 400, err_msg
    end

    local consumer_groups = get_consumer_groups()
    local err_msg = check_resources_reference(consumer_groups, id, true, "consumer_group")
    if err_msg then
        return 400, err_msg
    end

    local global_rules = get_global_rules()
    err_msg = check_resources_reference(global_rules, id, true, "global_rules")
    if err_msg then
        return 400, err_msg
    end

    return nil, nil
end


return resource.new({
    name = "upstreams",
    kind = "upstream",
    schema = core.schema.upstream,
    checker = check_conf,
    encrypt_conf = encrypt_conf,
    delete_checker = delete_checker
})
