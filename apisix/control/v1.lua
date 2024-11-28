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
local require = require
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local upstream_mod = require("apisix.upstream")
local get_upstreams = upstream_mod.upstreams
local collectgarbage = collectgarbage
local ipairs = ipairs
local pcall = pcall
local str_format = string.format
local ngx = ngx
local ngx_var = ngx.var
local events = require("apisix.events")


local _M = {}

_M.RELOAD_PLUGINS_EVENT = 'control-api-plugins-reload'
_M.RELOAD_HOSTS_EVENT = 'control-api-hosts-reload'

function _M.schema()
    local http_plugins, stream_plugins = plugin.get_all({
        version = true,
        priority = true,
        schema = true,
        metadata_schema = true,
        consumer_schema = true,
        type = true,
        scope = true,
    })
    local schema = {
        main = {
            consumer = core.schema.consumer,
            consumer_group = core.schema.consumer_group,
            global_rule = core.schema.global_rule,
            plugin_config = core.schema.plugin_config,
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
        plugins = http_plugins,
        stream_plugins = stream_plugins,
    }
    return 200, schema
end


local healthcheck
local function extra_checker_info(value)
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end

    local name = upstream_mod.get_healthchecker_name(value)
    local nodes, err = healthcheck.get_target_list(name, "upstream-healthcheck")
    if err then
        core.log.error("healthcheck.get_target_list failed: ", err)
    end
    return {
        name = value.key,
        nodes = nodes,
    }
end


local function get_checker_type(checks)
    if checks.active and checks.active.type then
        return checks.active.type
    elseif checks.passive and checks.passive.type then
        return checks.passive.type
    end
end


local function iter_and_add_healthcheck_info(infos, values)
    if not values then
        return
    end

    for _, value in core.config_util.iterate_values(values) do
        local checks = value.value.checks or (value.value.upstream and value.value.upstream.checks)
        if checks then
            local info = extra_checker_info(value)
            info.type = get_checker_type(checks)
            core.table.insert(infos, info)
        end
    end
end


local HTML_TEMPLATE = [[
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>APISIX upstream check status</title>
</head>
<body>
<h1>APISIX upstream check status</h1>
<table style="background-color:white" cellspacing="0" cellpadding="3" border="1">
  <tr bgcolor="#C0C0C0">
    <th>Index</th>
    <th>Upstream</th>
    <th>Check type</th>
    <th>Host</th>
    <th>Status</th>
    <th>Success counts</th>
    <th>TCP Failures</th>
    <th>HTTP Failures</th>
    <th>TIMEOUT Failures</th>
  </tr>
{% local i = 0 %}
{% for _, stat in ipairs(stats) do %}
{% for _, node in ipairs(stat.nodes) do %}
{% i = i + 1 %}
  {% if node.status == "healthy" or node.status == "mostly_healthy" then %}
  <tr>
  {% else %}
  <tr bgcolor="#FF0000">
  {% end %}
    <td>{* i *}</td>
    <td>{* stat.name *}</td>
    <td>{* stat.type *}</td>
    <td>{* node.ip .. ":" .. node.port *}</td>
    <td>{* node.status *}</td>
    <td>{* node.counter.success *}</td>
    <td>{* node.counter.tcp_failure *}</td>
    <td>{* node.counter.http_failure *}</td>
    <td>{* node.counter.timeout_failure *}</td>
  </tr>
{% end %}
{% end %}
</table>
</body>
</html>
]]

local html_render

local function try_render_html(data)
    if not html_render then
        local template = require("resty.template")
        html_render = template.compile(HTML_TEMPLATE)
    end
    local accept = ngx_var.http_accept
    if accept and accept:find("text/html") then
        local ok, out = pcall(html_render, data)
        if not ok then
            local err = str_format("HTML template rendering: %s", out)
            core.log.error(err)
            return nil, err
        end
        return out
    end
end


local function _get_health_checkers()
    local infos = {}
    local routes = get_routes()
    iter_and_add_healthcheck_info(infos, routes)
    local services = get_services()
    iter_and_add_healthcheck_info(infos, services)
    local upstreams = get_upstreams()
    iter_and_add_healthcheck_info(infos, upstreams)
    return infos
end


function _M.get_health_checkers()
    local infos = _get_health_checkers()
    local out, err = try_render_html({stats=infos})
    if out then
        core.response.set_header("Content-Type", "text/html")
        return 200, out
    end
    if err then
        return 503, {error_msg = err}
    end

    return 200, infos
end


local function iter_and_find_healthcheck_info(values, src_type, src_id)
    if not values then
        return nil, str_format("%s[%s] not found", src_type, src_id)
    end

    for _, value in core.config_util.iterate_values(values) do
        if value.value.id == src_id then
            local checks = value.value.checks or
                (value.value.upstream and value.value.upstream.checks)
            if not checks then
                return nil, str_format("no checker for %s[%s]", src_type, src_id)
            end

            local info = extra_checker_info(value)
            info.type = get_checker_type(checks)
            return info
        end
    end

    return nil, str_format("%s[%s] not found", src_type, src_id)
end


function _M.get_health_checker()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    core.log.info("healthcheck uri: ", core.json.delay_encode(uri_segs))

    local src_type, src_id = uri_segs[4], uri_segs[5]
    if not src_id then
        return 404, {error_msg = str_format("missing src id for src type %s", src_type)}
    end

    local values
    if src_type == "routes" then
        values = get_routes()
    elseif src_type == "services" then
        values = get_services()
    elseif src_type == "upstreams" then
        values = get_upstreams()
    else
        return 400, {error_msg = str_format("invalid src type %s", src_type)}
    end

    local info, err = iter_and_find_healthcheck_info(values, src_type, src_id)
    if not info then
        return 404, {error_msg = err}
    end

    local out, err = try_render_html({stats={info}})
    if out then
        core.response.set_header("Content-Type", "text/html")
        return 200, out
    end
    if err then
        return 503, {error_msg = err}
    end

    return 200, info
end

local function iter_add_get_routes_info(values, route_id)
    local infos = {}
    for _, route in core.config_util.iterate_values(values) do
        local new_route = core.table.deepcopy(route)
        if new_route.value.upstream and new_route.value.upstream.parent then
            new_route.value.upstream.parent = nil
        end
        core.table.insert(infos, new_route)
        -- check the route id
        if route_id and route.value.id == route_id then
            return new_route
        end
    end
    if not route_id then
        return infos
    end
    return nil
end

function _M.dump_all_routes_info()
    local routes = get_routes()
    local infos = iter_add_get_routes_info(routes, nil)
    return 200, infos
end

function _M.dump_route_info()
    local routes = get_routes()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    local route_id = uri_segs[4]
    local route = iter_add_get_routes_info(routes, route_id)
    if not route then
        return 404, {error_msg = str_format("route[%s] not found", route_id)}
    end
    return 200, route
end

local function iter_add_get_upstream_info(values, upstream_id)
    if not values then
        return nil
    end

    local infos = {}
    for _, upstream in core.config_util.iterate_values(values) do
        local new_upstream = core.table.deepcopy(upstream)
        core.table.insert(infos, new_upstream)
        if new_upstream.value and new_upstream.value.parent then
            new_upstream.value.parent = nil
        end
        -- check the upstream id
        if upstream_id and upstream.value.id == upstream_id then
            return new_upstream
        end
    end
    if not upstream_id then
        return infos
    end
    return nil
end

function _M.dump_all_upstreams_info()
    local upstreams = get_upstreams()
    local infos = iter_add_get_upstream_info(upstreams, nil)
    return 200, infos
end

function _M.dump_upstream_info()
    local upstreams = get_upstreams()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    local upstream_id = uri_segs[4]
    local upstream = iter_add_get_upstream_info(upstreams, upstream_id)
    if not upstream then
        return 404, {error_msg = str_format("upstream[%s] not found", upstream_id)}
    end
    return 200, upstream
end

function _M.trigger_gc()
    -- TODO: find a way to trigger GC in the stream subsystem
    collectgarbage()
    return 200
end


local function iter_add_get_services_info(values, svc_id)
    local infos = {}
    for _, svc in core.config_util.iterate_values(values) do
        local new_svc = core.table.deepcopy(svc)
        if new_svc.value.upstream and new_svc.value.upstream.parent then
            new_svc.value.upstream.parent = nil
        end
        core.table.insert(infos, new_svc)
        -- check the service id
        if svc_id and svc.value.id == svc_id then
            return new_svc
        end
    end
    if not svc_id then
        return infos
    end
    return nil
end

function _M.dump_all_services_info()
    local services = get_services()
    local infos = iter_add_get_services_info(services, nil)
    return 200, infos
end

function _M.dump_service_info()
    local services = get_services()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    local svc_id = uri_segs[4]
    local info = iter_add_get_services_info(services, svc_id)
    if not info then
        return 404, {error_msg = str_format("service[%s] not found", svc_id)}
    end
    return 200, info
end

function _M.dump_all_plugin_metadata()
    local names = core.config.local_conf().plugins
    local metadatas = core.table.new(0, #names)
    for _, name in ipairs(names) do
        local metadata = plugin.plugin_metadata(name)
        if metadata then
            core.table.insert(metadatas, metadata.value)
        end
    end
    return 200, metadatas
end

function _M.dump_plugin_metadata()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    local name = uri_segs[4]
    local metadata = plugin.plugin_metadata(name)
    if not metadata then
        return 404, {error_msg = str_format("plugin metadata[%s] not found", name)}
    end
    return 200, metadata.value
end

function _M.post_reload_plugins()
    local success, err = events:post(_M.RELOAD_PLUGINS_EVENT, ngx.req.get_method(), ngx.time())
    if not success then
        core.response.exit(503, err)
    end

    core.response.exit(200, "done")
end

function _M.post_reload_hosts()
    local success, err = events:post(_M.RELOAD_HOSTS_EVENT, ngx.req.get_method(), ngx.time())
    if not success then
        core.response.exit(503, err)
    end

    core.response.exit(200, "done")
end

function _M.get_hosts()
    local hosts = core.resolver.get_hosts()
    return 200, hosts
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
        handler = _M.get_health_checkers,
    },
    -- /v1/healthcheck/{src_type}/{src_id}
    {
        methods = {"GET"},
        uris = {"/healthcheck/*"},
        handler = _M.get_health_checker,
    },
    -- /v1/gc
    {
        methods = {"POST"},
        uris = {"/gc"},
        handler = _M.trigger_gc,
    },
    -- /v1/routes
    {
        methods = {"GET"},
        uris = {"/routes"},
        handler = _M.dump_all_routes_info,
    },
    -- /v1/route/*
    {
        methods = {"GET"},
        uris = {"/route/*"},
        handler = _M.dump_route_info,
    },
    -- /v1/services
    {
        methods = {"GET"},
        uris = {"/services"},
        handler = _M.dump_all_services_info
    },
    -- /v1/service/*
    {
        methods = {"GET"},
        uris = {"/service/*"},
        handler = _M.dump_service_info
    },
    -- /v1/upstreams
    {
        methods = {"GET"},
        uris = {"/upstreams"},
        handler = _M.dump_all_upstreams_info,
    },
    -- /v1/upstream/*
    {
        methods = {"GET"},
        uris = {"/upstream/*"},
        handler = _M.dump_upstream_info,
    },
    -- /v1/plugin_metadatas
    {
        methods = {"GET"},
        uris = {"/plugin_metadatas"},
        handler = _M.dump_all_plugin_metadata,
    },
    -- /v1/plugin_metadata/*
    {
        methods = {"GET"},
        uris = {"/plugin_metadata/*"},
        handler = _M.dump_plugin_metadata,
    },
    -- /v1/plugins/reload
    {
        methods = {"PUT"},
        uris = {"/plugins/reload"},
        handler = _M.post_reload_plugins,
    },
    -- /v1/hosts/reload
    {
        methods = {"PUT"},
        uris = {"/hosts/reload"},
        handler = _M.post_reload_hosts,
    },
    -- /v1/hosts
    {
        methods = {"GET"},
        uris = {"/hosts"},
        handler = _M.get_hosts,
    },
    get_health_checkers = _get_health_checkers,
    reload_plugins_event = _M.RELOAD_PLUGINS_EVENT,
    reload_hosts_event = _M.RELOAD_HOSTS_EVENT,
}
