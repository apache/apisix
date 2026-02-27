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
local ngx_time = ngx.time


local function update_warm_up_timestamps(conf, old_conf)
    if not conf or not conf.warm_up_conf then
        return
    end
    if not conf.nodes or not core.table.isarray(conf.nodes) then
        return
    end

    local previous_node_update_time = {}
    if old_conf and old_conf.nodes and core.table.isarray(old_conf.nodes) then
        for _, node in ipairs(old_conf.nodes) do
            local key = (node.domain or node.host) .. ":" .. tostring(node.port)
            previous_node_update_time[key] = node.update_time
        end
    end

    for _, node in ipairs(conf.nodes) do
        if not node.update_time then
            local key = (node.domain or node.host) .. ":" .. tostring(node.port)
            node.update_time = previous_node_update_time[key] or ngx_time()
        end
    end
end


local function update_node_warm_up_timestamps(id, conf)
    if not id then
        return
    end

    local old_conf
    local upstreams = core.config.fetch_created_obj("/upstreams")
    if upstreams then
        local upstream = upstreams:get(tostring(id))
        if upstream then
            old_conf = upstream.value
        end
    end

    update_warm_up_timestamps(conf, old_conf)
end


local function initialize_conf(id, conf)
    update_node_warm_up_timestamps(id, conf)
end


local function check_conf(id, conf, need_id)
    local ok, err = apisix_upstream.check_upstream_conf(conf)
    if not ok then
        return nil, {error_msg = err}
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


local upstreams = resource.new({
    name = "upstreams",
    kind = "upstream",
    schema = core.schema.upstream,
    checker = check_conf,
    encrypt_conf = encrypt_conf,
    delete_checker = delete_checker,
    initialize_conf = initialize_conf,
})

upstreams.update_warm_up_timestamps = update_warm_up_timestamps

return upstreams
