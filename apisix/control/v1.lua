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
local plugin = require("apisix.plugin")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local upstream_mod = require("apisix.upstream")
local get_upstreams = upstream_mod.upstreams
local ipairs = ipairs


local _M = {}


function _M.schema()
    local schema = {
        main = {
            consumer = core.schema.consumer,
            global_rule = core.schema.global_rule,
            plugins = core.schema.plugins,
            proto = core.schema.proto,
            route = core.schema.route,
            service = core.schema.service,
            ssl = core.schema.ssl,
            stream_route = core.schema.stream_route,
            upstream = core.schema.upstream,
            upstream_hash_header_schema = core.schema.upstream_hash_header_schema,
            upstream_hash_vars_schema = core.schema.upstream_hash_vars_schema,
        },
        plugins = plugin.get_all({
            version = true,
            priority = true,
            schema = true,
            metadata_schema = true,
            consumer_schema = true,
            type = true,
        }),
    }
    return 200, schema
end


local function iter_and_add_checker(infos, values, src)
    if not values then
        return
    end

    for _, value in core.config_util.iterate_values(values) do
        if value.checker then
            local checker = value.checker
            local upstream = value.checker_upstream
            local host = upstream.checks and upstream.checks.active and upstream.checks.active.host
            local port = upstream.checks and upstream.checks.active and upstream.checks.active.port
            local nodes = upstream.nodes
            local health_nodes = core.table.new(#nodes, 0)
            for _, node in ipairs(nodes) do
                local ok = checker:get_target_status(node.host, port or node.port, host)
                if ok then
                    core.table.insert(health_nodes, node)
                end
            end

            local conf = value.value
            core.table.insert(infos, {
                name = upstream_mod.get_healthchecker_name(value),
                src_id = conf.id,
                src_type = src,
                nodes = nodes,
                health_nodes = health_nodes,
            })
        end
    end
end


function _M.healthcheck()
    local infos = {}
    local routes = get_routes()
    iter_and_add_checker(infos, routes, "routes")
    local services = get_services()
    iter_and_add_checker(infos, services, "services")
    local upstreams = get_upstreams()
    iter_and_add_checker(infos, upstreams, "upstreams")
    return 200, infos
end


return {
    -- /v1/schema
    {
        methods = {"GET"},
        uris = {"/schema"},
        handler = _M.schema,
    },
    -- /v1/healthcheck
    {
        methods = {"GET"},
        uris = {"/healthcheck"},
        handler = _M.healthcheck,
    }
}
