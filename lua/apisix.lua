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
local require       = require
local core          = require("apisix.core")
local plugin        = require("apisix.plugin")
local service_fetch = require("apisix.http.service").get
local admin_init    = require("apisix.admin.init")
local get_var       = require("resty.ngxvar").fetch
local router        = require("apisix.router")
local ipmatcher     = require("resty.ipmatcher")
local ngx           = ngx
local get_method    = ngx.req.get_method
local ngx_exit      = ngx.exit
local math          = math
local error         = error
local ipairs        = ipairs
local pairs         = pairs
local tostring      = tostring
local load_balancer


local parsed_domain = core.lrucache.new({
    ttl = 300, count = 512
})


local _M = {version = 0.3}


function _M.http_init()
    require("resty.core")

    if require("ffi").os == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")

    --
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx.now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)

    core.id.init()
end


function _M.http_init_worker()
    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end

    require("apisix.balancer").init_worker()
    load_balancer = require("apisix.balancer").run
    require("apisix.admin.init").init_worker()

    router.http_init_worker()
    require("apisix.http.service").init_worker()
    plugin.init_worker()
    require("apisix.consumer").init_worker()

    if core.config == require("apisix.core.config_yaml") then
        core.config.init_worker()
    end

    require("apisix.debug").init_worker()
end


local function run_plugin(phase, plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugins = plugins or api_ctx.plugins
    if not plugins then
        return api_ctx
    end

    if phase == "balancer" then
        local balancer_name = api_ctx.balancer_name
        local balancer_plugin = api_ctx.balancer_plugin
        if balancer_name and balancer_plugin then
            local phase_fun = balancer_plugin[phase]
            phase_fun(balancer_plugin, api_ctx)
            return api_ctx
        end

        for i = 1, #plugins, 2 do
            local phase_fun = plugins[i][phase]
            if phase_fun and
               (not balancer_name or balancer_name == plugins[i].name) then
                phase_fun(plugins[i + 1], api_ctx)
                if api_ctx.balancer_name == plugins[i].name then
                    api_ctx.balancer_plugin = plugins[i]
                    return api_ctx
                end
            end
        end
        return api_ctx
    end

    if phase ~= "log" then
        for i = 1, #plugins, 2 do
            local phase_fun = plugins[i][phase]
            if phase_fun then
                local code, body = phase_fun(plugins[i + 1], api_ctx)
                if code or body then
                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    for i = 1, #plugins, 2 do
        local phase_fun = plugins[i][phase]
        if phase_fun then
            phase_fun(plugins[i + 1], api_ctx)
        end
    end

    return api_ctx
end


function _M.http_ssl_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    local ok, err = router.router_ssl.match_and_set(api_ctx)
    if not ok then
        if err then
            core.log.warn("failed to fetch ssl config: ", err)
        end
    end
end


local function parse_domain_in_up(up, ver)
    local local_conf = core.config.local_conf()
    local dns_resolver = local_conf and local_conf.apisix and
                         local_conf.apisix.dns_resolver
    local new_nodes = core.table.new(0, 8)

    for addr, weight in pairs(up.value.nodes) do
        local host, port = core.utils.parse_addr(addr)
        if not ipmatcher.parse_ipv4(host) and
           not ipmatcher.parse_ipv6(host) then
            local ip_info = core.utils.dns_parse(dns_resolver, host)
            core.log.info("parse addr: ", core.json.delay_encode(ip_info),
                          " resolver: ", core.json.delay_encode(dns_resolver),
                          " addr: ", addr)
            if ip_info and ip_info.address then
                new_nodes[ip_info.address .. ":" .. port] = weight
                core.log.info("dns resolver domain: ", host, " to ",
                              ip_info.address)
            end
        else
            new_nodes[addr] = weight
        end
    end

    up.dns_value = core.table.clone(up.value)
    up.dns_value.nodes = new_nodes
    core.log.info("parse upstream which contain domain: ",
                  core.json.delay_encode(up))
    return up
end


local function parse_domain_in_route(route, ver)
    local local_conf = core.config.local_conf()
    local dns_resolver = local_conf and local_conf.apisix and
                         local_conf.apisix.dns_resolver
    local new_nodes = core.table.new(0, 8)

    for addr, weight in pairs(route.value.upstream.nodes) do
        local host, port = core.utils.parse_addr(addr)
        if not ipmatcher.parse_ipv4(host) and
           not ipmatcher.parse_ipv6(host) then
            local ip_info = core.utils.dns_parse(dns_resolver, host)
            core.log.info("parse addr: ", core.json.delay_encode(ip_info),
                          " resolver: ", core.json.delay_encode(dns_resolver),
                          " addr: ", addr)
            if ip_info and ip_info.address then
                new_nodes[ip_info.address .. ":" .. port] = weight
                core.log.info("dns resolver domain: ", host, " to ",
                              ip_info.address)
            end
        else
            new_nodes[addr] = weight
        end
    end

    route.dns_value = core.table.deepcopy(route.value)
    route.dns_value.upstream.nodes = new_nodes
    core.log.info("parse route which contain domain: ",
                  core.json.delay_encode(route))
    return route
end


function _M.http_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    -- load and run global rule
    if router.global_rules and router.global_rules.values
       and #router.global_rules.values > 0 then
        local plugins = core.tablepool.fetch("plugins", 32, 0)
        for _, global_rule in ipairs(router.global_rules.values) do
            api_ctx.conf_type = "global_rule"
            api_ctx.conf_version = global_rule.modifiedIndex
            api_ctx.conf_id = global_rule.value.id

            core.table.clear(plugins)
            api_ctx.plugins = plugin.filter(global_rule, plugins)
            run_plugin("rewrite", plugins, api_ctx)
            run_plugin("access", plugins, api_ctx)
        end

        core.tablepool.release("plugins", plugins)
        api_ctx.plugins = nil
        api_ctx.conf_type = nil
        api_ctx.conf_version = nil
        api_ctx.conf_id = nil
    end

    router.router_http.match(api_ctx)

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if not route then
        return core.response.exit(404)
    end

    if route.value.service_protocol == "grpc" then
        return ngx.exec("@grpc_pass")
    end

    if route.value.service_id then
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        local changed
        route, changed = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route

        if changed then
            api_ctx.conf_type = "route&service"
            api_ctx.conf_version = route.modifiedIndex .. "&"
                                   .. service.modifiedIndex
            api_ctx.conf_id = route.value.id .. "&"
                              .. service.value.id
        else
            api_ctx.conf_type = "service"
            api_ctx.conf_version = service.modifiedIndex
            api_ctx.conf_id = service.value.id
        end
    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end

    local up_id = route.value.upstream_id
    if up_id then
        local upstreams_etcd = core.config.fetch_created_obj("/upstreams")
        if upstreams_etcd then
            local upstream = upstreams_etcd:get(tostring(up_id))
            if upstream.has_domain then
                parsed_domain(upstream, api_ctx.conf_version,
                              parse_domain_in_up, upstream)
            end
        end

    elseif route.has_domain then
        route = parsed_domain(route, api_ctx.conf_version,
                              parse_domain_in_route, route)
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.filter(route, plugins)

    run_plugin("rewrite", plugins, api_ctx)
    if api_ctx.consumer then
        local changed
        route, changed = plugin.merge_consumer_route(route, api_ctx.consumer)
        if changed then
            core.table.clear(api_ctx.plugins)
            api_ctx.plugins = plugin.filter(route, api_ctx.plugins)
        end
    end
    run_plugin("access", plugins, api_ctx)
end


function _M.grpc_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    router.router_http.match(api_ctx)

    core.log.info("route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if not route then
        return core.response.exit(404)
    end

    if route.value.service_id then
        -- core.log.info("matched route: ", core.json.delay_encode(route.value))
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        local changed
        route, changed = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route

        if changed then
            api_ctx.conf_type = "route&service"
            api_ctx.conf_version = route.modifiedIndex .. "&"
                                   .. service.modifiedIndex
            api_ctx.conf_id = route.value.id .. "&"
                              .. service.value.id
        else
            api_ctx.conf_type = "service"
            api_ctx.conf_version = service.modifiedIndex
            api_ctx.conf_id = service.value.id
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.filter(route, plugins)

    run_plugin("rewrite", plugins, api_ctx)
    run_plugin("access", plugins, api_ctx)
end


function _M.http_header_filter_phase()
    run_plugin("header_filter")
end


function _M.http_body_filter_phase()
    run_plugin("body_filter")
end


function _M.http_log_phase()
    local api_ctx = run_plugin("log")
    if api_ctx then
        if api_ctx.uri_parse_param then
            core.tablepool.release("uri_parse_param", api_ctx.uri_parse_param)
        end

        core.ctx.release_vars(api_ctx)
        if api_ctx.plugins then
            core.tablepool.release("plugins", api_ctx.plugins)
        end

        core.tablepool.release("api_ctx", api_ctx)
    end
end


function _M.http_balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return core.response.exit(500)
    end

    -- first time
    if not api_ctx.balancer_name then
        run_plugin("balancer", nil, api_ctx)
        if api_ctx.balancer_name then
            return
        end
    end

    if api_ctx.balancer_name and api_ctx.balancer_name ~= "default" then
        return run_plugin("balancer", nil, api_ctx)
    end

    api_ctx.balancer_name = "default"
    load_balancer(api_ctx.matched_route, api_ctx)
end


do
    local router

function _M.http_admin()
    if not router then
        router = admin_init.get()
    end

    -- core.log.info("uri: ", get_var("uri"), " method: ", get_method())
    local ok = router:dispatch(get_var("uri"), {method = get_method()})
    if not ok then
        ngx_exit(404)
    end
end

end -- do


function _M.stream_init()
    core.log.info("enter stream_init")
end


function _M.stream_init_worker()
    core.log.info("enter stream_init_worker")
    router.stream_init_worker()
    plugin.init_worker()

    load_balancer = require("apisix.balancer").run
end


function _M.stream_preread_phase()
    core.log.info("enter stream_preread_phase")

    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    router.router_stream.match(api_ctx)

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local matched_route = api_ctx.matched_route
    if not matched_route then
        return ngx_exit(1)
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.stream_filter(matched_route, plugins)
    -- core.log.info("valid plugins: ", core.json.delay_encode(plugins, true))

    run_plugin("preread", plugins, api_ctx)
end


function _M.stream_balancer_phase()
    core.log.info("enter stream_balancer_phase")
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return ngx_exit(1)
    end

    -- first time
    if not api_ctx.balancer_name then
        run_plugin("balancer", nil, api_ctx)
        if api_ctx.balancer_name then
            return
        end
    end

    if api_ctx.balancer_name and api_ctx.balancer_name ~= "default" then
        return run_plugin("balancer", nil, api_ctx)
    end

    api_ctx.balancer_name = "default"
    load_balancer(api_ctx.matched_route, api_ctx)
end


function _M.stream_log_phase()
    core.log.info("enter stream_log_phase")
    -- core.ctx.release_vars(api_ctx)
    run_plugin("log")
end


return _M
