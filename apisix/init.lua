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
local require         = require
-- set the JIT options before any code, to prevent error "changing jit stack size is not
-- allowed when some regexs have already been compiled and cached"
if require("ffi").os == "Linux" then
    require("ngx.re").opt("jit_stack_size", 200 * 1024)
end

require("jit.opt").start("minstitch=2", "maxtrace=4000",
                         "maxrecord=8000", "sizemcode=64",
                         "maxmcode=4000", "maxirconst=1000")

require("apisix.patch").patch()
local core            = require("apisix.core")
local conf_server     = require("apisix.conf_server")
local plugin          = require("apisix.plugin")
local plugin_config   = require("apisix.plugin_config")
local consumer_group  = require("apisix.consumer_group")
local script          = require("apisix.script")
local service_fetch   = require("apisix.http.service").get
local admin_init      = require("apisix.admin.init")
local get_var         = require("resty.ngxvar").fetch
local router          = require("apisix.router")
local apisix_upstream = require("apisix.upstream")
local apisix_secret   = require("apisix.secret")
local set_upstream    = apisix_upstream.set_by_route
local apisix_ssl      = require("apisix.ssl")
local upstream_util   = require("apisix.utils.upstream")
local xrpc            = require("apisix.stream.xrpc")
local ctxdump         = require("resty.ctxdump")
local debug           = require("apisix.debug")
local pubsub_kafka    = require("apisix.pubsub.kafka")
local ngx             = ngx
local get_method      = ngx.req.get_method
local ngx_exit        = ngx.exit
local math            = math
local error           = error
local ipairs          = ipairs
local ngx_now         = ngx.now
local ngx_var         = ngx.var
local re_split        = require("ngx.re").split
local str_byte        = string.byte
local str_sub         = string.sub
local tonumber        = tonumber
local type            = type
local pairs           = pairs
local control_api_router

local is_http = false
if ngx.config.subsystem == "http" then
    is_http = true
    control_api_router = require("apisix.control.router")
end

local ok, apisix_base_flags = pcall(require, "resty.apisix.patch")
if not ok then
    apisix_base_flags = {}
end

local load_balancer
local local_conf
local ver_header = "APISIX/" .. core.version.VERSION


local _M = {version = 0.4}


function _M.http_init(args)
    core.resolver.init_resolver(args)
    core.id.init()
    core.env.init()

    local process = require("ngx.process")
    local ok, err = process.enable_privileged_agent()
    if not ok then
        core.log.error("failed to enable privileged_agent: ", err)
    end

    if core.config.init then
        local ok, err = core.config.init()
        if not ok then
            core.log.error("failed to load the configuration: ", err)
        end
    end

    xrpc.init()
    conf_server.init()
end


function _M.http_init_worker()
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx_now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)
    -- for testing only
    core.log.info("random test in [1, 10000]: ", math.random(1, 10000))

    -- Because go's scheduler doesn't work after fork, we have to load the gRPC module
    -- in each worker.
    core.grpc = require("apisix.core.grpc")
    if type(core.grpc) ~= "table" then
        core.grpc = nil
    end

    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end
    local discovery = require("apisix.discovery.init").discovery
    if discovery and discovery.init_worker then
        discovery.init_worker()
    end
    require("apisix.balancer").init_worker()
    load_balancer = require("apisix.balancer")
    require("apisix.admin.init").init_worker()

    require("apisix.timers").init_worker()

    require("apisix.debug").init_worker()

    if core.config.init_worker then
        local ok, err = core.config.init_worker()
        if not ok then
            core.log.error("failed to init worker process of ", core.config.type,
                           " config center, err: ", err)
        end
    end

    plugin.init_worker()
    router.http_init_worker()
    require("apisix.http.service").init_worker()
    plugin_config.init_worker()
    require("apisix.consumer").init_worker()
    consumer_group.init_worker()
    apisix_secret.init_worker()

    apisix_upstream.init_worker()
    require("apisix.plugins.ext-plugin.init").init_worker()

    local_conf = core.config.local_conf()

    if local_conf.apisix and local_conf.apisix.enable_server_tokens == false then
        ver_header = "APISIX"
    end
end


function _M.http_exit_worker()
    -- TODO: we can support stream plugin later - currently there is not `destory` method
    -- in stream plugins
    plugin.exit_worker()
    require("apisix.plugins.ext-plugin.init").exit_worker()
end


function _M.http_ssl_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    ngx_ctx.api_ctx = api_ctx

    local ok, err = router.router_ssl.match_and_set(api_ctx)

    core.tablepool.release("api_ctx", api_ctx)
    ngx_ctx.api_ctx = nil

    if not ok then
        if err then
            core.log.error("failed to fetch ssl config: ", err)
        end
        ngx_exit(-1)
    end
end


local function stash_ngx_ctx()
    local ref = ctxdump.stash_ngx_ctx()
    core.log.info("stash ngx ctx: ", ref)
    ngx_var.ctx_ref = ref
end


local function fetch_ctx()
    local ref = ngx_var.ctx_ref
    core.log.info("fetch ngx ctx: ", ref)
    local ctx = ctxdump.apply_ngx_ctx(ref)
    ngx_var.ctx_ref = ''
    return ctx
end


local function parse_domain_in_route(route)
    local nodes = route.value.upstream.nodes
    local new_nodes, err = upstream_util.parse_domain_for_nodes(nodes)
    if not new_nodes then
        return nil, err
    end

    local up_conf = route.dns_value and route.dns_value.upstream
    local ok = upstream_util.compare_upstream_node(up_conf, new_nodes)
    if ok then
        return route
    end

    -- don't modify the modifiedIndex to avoid plugin cache miss because of DNS resolve result
    -- has changed

    -- Here we copy the whole route instead of part of it,
    -- so that we can avoid going back from route.value to route during copying.
    route.dns_value = core.table.deepcopy(route).value
    route.dns_value.upstream.nodes = new_nodes
    core.log.info("parse route which contain domain: ",
                  core.json.delay_encode(route, true))
    return route
end


local function set_upstream_host(api_ctx, picked_server)
    local up_conf = api_ctx.upstream_conf
    if up_conf.pass_host then
        api_ctx.pass_host = up_conf.pass_host
        api_ctx.upstream_host = up_conf.upstream_host
    end

    local pass_host = api_ctx.pass_host or "pass"
    if pass_host == "pass" then
        return
    end

    if pass_host == "rewrite" then
        api_ctx.var.upstream_host = api_ctx.upstream_host
        return
    end

    api_ctx.var.upstream_host = picked_server.upstream_host
end


local function set_upstream_headers(api_ctx, picked_server)
    set_upstream_host(api_ctx, picked_server)

    local proto = api_ctx.var.http_x_forwarded_proto
    if proto then
        api_ctx.var.var_x_forwarded_proto = proto
    end

    local x_forwarded_host = api_ctx.var.http_x_forwarded_host
    if x_forwarded_host then
        api_ctx.var.var_x_forwarded_host = x_forwarded_host
    end

    local port = api_ctx.var.http_x_forwarded_port
    if port then
        api_ctx.var.var_x_forwarded_port = port
    end
end


local function verify_tls_client(ctx)
    if apisix_base_flags.client_cert_verified_in_handshake then
        -- For apisix-base, there is no need to rematch SSL rules as the invalid
        -- connections are already rejected in the handshake
        return true
    end

    local matched = router.router_ssl.match_and_set(ctx, true)
    if not matched then
        return true
    end

    local matched_ssl = ctx.matched_ssl
    if matched_ssl.value.client and apisix_ssl.support_client_verification() then
        local res = ngx_var.ssl_client_verify
        if res ~= "SUCCESS" then
            if res == "NONE" then
                core.log.error("client certificate was not present")
            else
                core.log.error("client certificate verification is not passed: ", res)
            end

            return false
        end
    end

    return true
end


local function verify_https_client(ctx)
    local scheme = ctx.var.scheme
    if scheme ~= "https" then
        return true
    end

    local host = ctx.var.host
    local matched = router.router_ssl.match_and_set(ctx, true, host)
    if not matched then
        return true
    end

    local matched_ssl = ctx.matched_ssl
    if matched_ssl.value.client and apisix_ssl.support_client_verification() then
        local verified = apisix_base_flags.client_cert_verified_in_handshake
        if not verified then
            -- vanilla OpenResty requires to check the verification result
            local res = ctx.var.ssl_client_verify
            if res ~= "SUCCESS" then
                if res == "NONE" then
                    core.log.error("client certificate was not present")
                else
                    core.log.error("client certificate verification is not passed: ", res)
                end

                return false
            end
        end

        local sni = apisix_ssl.server_name()
        if sni ~= host then
            -- There is a case that the user configures a SSL object with `*.domain`,
            -- and the client accesses with SNI `a.domain` but uses Host `b.domain`.
            -- This case is complex and we choose to restrict the access until there
            -- is a stronge demand in real world.
            core.log.error("client certificate verified with SNI ", sni,
                           ", but the host is ", host)
            return false
        end
    end

    return true
end


local function normalize_uri_like_servlet(uri)
    local found = core.string.find(uri, ';')
    if not found then
        return uri
    end

    local segs, err = re_split(uri, "/", "jo")
    if not segs then
        return nil, err
    end

    local len = #segs
    for i = 1, len do
        local seg = segs[i]
        local pos = core.string.find(seg, ';')
        if pos then
            seg = seg:sub(1, pos - 1)
            -- reject bad uri which bypasses with ';'
            if seg == "." or seg == ".." then
                return nil, "dot segment with parameter"
            end
            if seg == "" and i < len then
                return nil, "empty segment with parameters"
            end

            segs[i] = seg

            seg = seg:lower()
            if seg == "%2e" or seg == "%2e%2e" then
                return nil, "encoded dot segment"
            end
        end
    end

    return core.table.concat(segs, '/')
end


local function common_phase(phase_name)
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugin.run_global_rules(api_ctx, api_ctx.global_rules, phase_name)

    if api_ctx.script_obj then
        script.run(phase_name, api_ctx)
        return api_ctx, true
    end

    return plugin.run_plugin(phase_name, nil, api_ctx)
end



function _M.handle_upstream(api_ctx, route, enable_websocket)
    local up_id = route.value.upstream_id

    -- used for the traffic-split plugin
    if api_ctx.upstream_id then
        up_id = api_ctx.upstream_id
    end

    if up_id then
        local upstream = apisix_upstream.get_by_id(up_id)
        if not upstream then
            if is_http then
                return core.response.exit(502)
            end

            return ngx_exit(1)
        end

        api_ctx.matched_upstream = upstream

    else
        if route.has_domain then
            local err
            route, err = parse_domain_in_route(route)
            if err then
                core.log.error("failed to get resolved route: ", err)
                return core.response.exit(500)
            end

            api_ctx.conf_version = route.modifiedIndex
            api_ctx.matched_route = route
        end

        local route_val = route.value

        api_ctx.matched_upstream = (route.dns_value and
                                    route.dns_value.upstream)
                                   or route_val.upstream
    end

    if api_ctx.matched_upstream and api_ctx.matched_upstream.tls and
        api_ctx.matched_upstream.tls.client_cert_id then

        local cert_id = api_ctx.matched_upstream.tls.client_cert_id
        local upstream_ssl = router.router_ssl.get_by_id(cert_id)
        if not upstream_ssl or upstream_ssl.type ~= "client" then
            local err  = upstream_ssl and
                "ssl type should be 'client'" or
                "ssl id [" .. cert_id .. "] not exits"
            core.log.error("failed to get ssl cert: ", err)

            if is_http then
                return core.response.exit(502)
            end

            return ngx_exit(1)
        end

        core.log.info("matched ssl: ",
                  core.json.delay_encode(upstream_ssl, true))
        api_ctx.upstream_ssl = upstream_ssl
    end

    if enable_websocket then
        api_ctx.var.upstream_upgrade    = api_ctx.var.http_upgrade
        api_ctx.var.upstream_connection = api_ctx.var.http_connection
        core.log.info("enabled websocket for route: ", route.value.id)
    end

    -- load balancer is not required by kafka upstream, so the upstream
    -- node selection process is intercepted and left to kafka to
    -- handle on its own
    if api_ctx.matched_upstream and api_ctx.matched_upstream.scheme == "kafka" then
        return pubsub_kafka.access(api_ctx)
    end

    local code, err = set_upstream(route, api_ctx)
    if code then
        core.log.error("failed to set upstream: ", err)
        core.response.exit(code)
    end

    local server, err = load_balancer.pick_server(route, api_ctx)
    if not server then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    api_ctx.picked_server = server

    set_upstream_headers(api_ctx, server)

    -- run the before_proxy method in access phase first to avoid always reinit request
    common_phase("before_proxy")

    local up_scheme = api_ctx.upstream_scheme
    if up_scheme == "grpcs" or up_scheme == "grpc" then
        stash_ngx_ctx()
        return ngx.exec("@grpc_pass")
    end

    if api_ctx.dubbo_proxy_enabled then
        stash_ngx_ctx()
        return ngx.exec("@dubbo_pass")
    end
end


function _M.http_access_phase()
    local ngx_ctx = ngx.ctx

    -- always fetch table from the table pool, we don't need a reused api_ctx
    local api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    ngx_ctx.api_ctx = api_ctx

    core.ctx.set_vars_meta(api_ctx)

    if not verify_https_client(api_ctx) then
        return core.response.exit(400)
    end

    debug.dynamic_debug(api_ctx)

    local uri = api_ctx.var.uri
    if local_conf.apisix then
        if local_conf.apisix.delete_uri_tail_slash then
            if str_byte(uri, #uri) == str_byte("/") then
                api_ctx.var.uri = str_sub(api_ctx.var.uri, 1, #uri - 1)
                core.log.info("remove the end of uri '/', current uri: ", api_ctx.var.uri)
            end
        end

        if local_conf.apisix.normalize_uri_like_servlet then
            local new_uri, err = normalize_uri_like_servlet(uri)
            if not new_uri then
                core.log.error("failed to normalize: ", err)
                return core.response.exit(400)
            end

            api_ctx.var.uri = new_uri
            -- forward the original uri so the servlet upstream
            -- can consume the param after ';'
            api_ctx.var.upstream_uri = uri
        end
    end

    -- To prevent being hacked by untrusted request_uri, here we
    -- record the normalized but not rewritten uri as request_uri,
    -- the original request_uri can be accessed via var.real_request_uri
    api_ctx.var.real_request_uri = api_ctx.var.request_uri
    api_ctx.var.request_uri = api_ctx.var.uri .. api_ctx.var.is_args .. (api_ctx.var.args or "")

    router.router_http.match(api_ctx)

    local route = api_ctx.matched_route
    if not route then
        -- run global rule when there is no matching route
        plugin.run_global_rules(api_ctx, router.global_rules, nil)

        core.log.info("not find any matched route")
        return core.response.exit(404,
                    {error_msg = "404 Route Not Found"})
    end

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local enable_websocket = route.value.enable_websocket

    if route.value.plugin_config_id then
        local conf = plugin_config.get(route.value.plugin_config_id)
        if not conf then
            core.log.error("failed to fetch plugin config by ",
                            "id: ", route.value.plugin_config_id)
            return core.response.exit(503)
        end

        route = plugin_config.merge(route, conf)
    end

    if route.value.service_id then
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        route = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route
        api_ctx.conf_type = "route&service"
        api_ctx.conf_version = route.modifiedIndex .. "&" .. service.modifiedIndex
        api_ctx.conf_id = route.value.id .. "&" .. service.value.id
        api_ctx.service_id = service.value.id
        api_ctx.service_name = service.value.name

        if enable_websocket == nil then
            enable_websocket = service.value.enable_websocket
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end
    api_ctx.route_id = route.value.id
    api_ctx.route_name = route.value.name

    -- run global rule
    plugin.run_global_rules(api_ctx, router.global_rules, nil)

    if route.value.script then
        script.load(route, api_ctx)
        script.run("access", api_ctx)

    else
        local plugins = plugin.filter(api_ctx, route)
        api_ctx.plugins = plugins

        plugin.run_plugin("rewrite", plugins, api_ctx)
        if api_ctx.consumer then
            local changed
            local group_conf

            if api_ctx.consumer.group_id then
                group_conf = consumer_group.get(api_ctx.consumer.group_id)
                if not group_conf then
                    core.log.error("failed to fetch consumer group config by ",
                        "id: ", api_ctx.consumer.group_id)
                    return core.response.exit(503)
                end
            end

            route, changed = plugin.merge_consumer_route(
                route,
                api_ctx.consumer,
                group_conf,
                api_ctx
            )

            core.log.info("find consumer ", api_ctx.consumer.username,
                          ", config changed: ", changed)

            if changed then
                api_ctx.matched_route = route
                core.table.clear(api_ctx.plugins)
                local phase = "rewrite_in_consumer"
                api_ctx.plugins = plugin.filter(api_ctx, route, api_ctx.plugins, nil, phase)
                -- rerun rewrite phase for newly added plugins in consumer
                plugin.run_plugin(phase, api_ctx.plugins, api_ctx)
            end
        end
        plugin.run_plugin("access", plugins, api_ctx)
    end

    _M.handle_upstream(api_ctx, route, enable_websocket)
end


function _M.dubbo_access_phase()
    ngx.ctx = fetch_ctx()
end


function _M.grpc_access_phase()
    ngx.ctx = fetch_ctx()

    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    local code, err = apisix_upstream.set_grpcs_upstream_param(api_ctx)
    if code then
        core.log.error("failed to set grpcs upstream param: ", err)
        core.response.exit(code)
    end
end


local function set_resp_upstream_status(up_status)
    local_conf = core.config.local_conf()

    if local_conf.apisix and local_conf.apisix.show_upstream_status_in_response_header then
        core.response.set_header("X-APISIX-Upstream-Status", up_status)
    elseif #up_status == 3 then
        if tonumber(up_status) >= 500 and tonumber(up_status) <= 599 then
            core.response.set_header("X-APISIX-Upstream-Status", up_status)
        end
    elseif #up_status > 3 then
        -- the up_status can be "502, 502" or "502, 502 : "
        local last_status
        if str_byte(up_status, -1) == str_byte(" ") then
            last_status = str_sub(up_status, -6, -3)
        else
            last_status = str_sub(up_status, -3)
        end

        if tonumber(last_status) >= 500 and tonumber(last_status) <= 599 then
            core.response.set_header("X-APISIX-Upstream-Status", up_status)
        end
    end
end


function _M.http_header_filter_phase()
    core.response.set_header("Server", ver_header)

    local up_status = get_var("upstream_status")
    if up_status then
        set_resp_upstream_status(up_status)
    end

    common_phase("header_filter")

    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    local debug_headers = api_ctx.debug_headers
    if debug_headers then
        local deduplicate = core.table.new(core.table.nkeys(debug_headers), 0)
        for k, v in pairs(debug_headers) do
            core.table.insert(deduplicate, k)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(deduplicate, ", "))
    end
end


function _M.http_body_filter_phase()
    common_phase("body_filter")
    common_phase("delayed_body_filter")
end


local function healthcheck_passive(api_ctx)
    local checker = api_ctx.up_checker
    if not checker then
        return
    end

    local up_conf = api_ctx.upstream_conf
    local passive = up_conf.checks.passive
    if not passive then
        return
    end

    core.log.info("enabled healthcheck passive")
    local host = up_conf.checks and up_conf.checks.active
                 and up_conf.checks.active.host
    local port = up_conf.checks and up_conf.checks.active
                 and up_conf.checks.active.port

    local resp_status = ngx.status
    local http_statuses = passive and passive.healthy and
                          passive.healthy.http_statuses
    core.log.info("passive.healthy.http_statuses: ",
                  core.json.delay_encode(http_statuses))
    if http_statuses then
        for i, status in ipairs(http_statuses) do
            if resp_status == status then
                checker:report_http_status(api_ctx.balancer_ip,
                                           port or api_ctx.balancer_port,
                                           host,
                                           resp_status)
            end
        end
    end

    http_statuses = passive and passive.unhealthy and
                    passive.unhealthy.http_statuses
    core.log.info("passive.unhealthy.http_statuses: ",
                  core.json.delay_encode(http_statuses))
    if not http_statuses then
        return
    end

    for i, status in ipairs(http_statuses) do
        if resp_status == status then
            checker:report_http_status(api_ctx.balancer_ip,
                                       port or api_ctx.balancer_port,
                                       host,
                                       resp_status)
        end
    end
end


function _M.http_log_phase()
    local api_ctx = common_phase("log")
    if not api_ctx then
        return
    end

    healthcheck_passive(api_ctx)

    if api_ctx.server_picker and api_ctx.server_picker.after_balance then
        api_ctx.server_picker.after_balance(api_ctx, false)
    end

    core.ctx.release_vars(api_ctx)
    if api_ctx.plugins then
        core.tablepool.release("plugins", api_ctx.plugins)
    end

    if api_ctx.curr_req_matched then
        core.tablepool.release("matched_route_record", api_ctx.curr_req_matched)
    end

    core.tablepool.release("api_ctx", api_ctx)
end


function _M.http_balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return core.response.exit(500)
    end

    load_balancer.run(api_ctx.matched_route, api_ctx, common_phase)
end


local function cors_admin()
    local_conf = core.config.local_conf()
    if not core.table.try_read_attr(local_conf, "deployment", "admin", "enable_admin_cors") then
        return
    end

    local method = get_method()
    if method == "OPTIONS" then
        core.response.set_header("Access-Control-Allow-Origin", "*",
            "Access-Control-Allow-Methods",
            "POST, GET, PUT, OPTIONS, DELETE, PATCH",
            "Access-Control-Max-Age", "3600",
            "Access-Control-Allow-Headers", "*",
            "Access-Control-Allow-Credentials", "true",
            "Content-Length", "0",
            "Content-Type", "text/plain")
        ngx_exit(200)
    end

    core.response.set_header("Access-Control-Allow-Origin", "*",
                            "Access-Control-Allow-Credentials", "true",
                            "Access-Control-Expose-Headers", "*",
                            "Access-Control-Max-Age", "3600")
end

local function add_content_type()
    core.response.set_header("Content-Type", "application/json")
end

do
    local router

function _M.http_admin()
    if not router then
        router = admin_init.get()
    end

    core.response.set_header("Server", ver_header)
    -- add cors rsp header
    cors_admin()

    -- add content type to rsp header
    add_content_type()

    -- core.log.info("uri: ", get_var("uri"), " method: ", get_method())
    local ok = router:dispatch(get_var("uri"), {method = get_method()})
    if not ok then
        ngx_exit(404)
    end
end

end -- do


function _M.http_control()
    local ok = control_api_router.match(get_var("uri"))
    if not ok then
        ngx_exit(404)
    end
end


function _M.stream_ssl_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    ngx_ctx.api_ctx = api_ctx

    local ok, err = router.router_ssl.match_and_set(api_ctx)

    core.tablepool.release("api_ctx", api_ctx)
    ngx_ctx.api_ctx = nil

    if not ok then
        if err then
            core.log.error("failed to fetch ssl config: ", err)
        end
        ngx_exit(-1)
    end
end


function _M.stream_init(args)
    core.log.info("enter stream_init")

    core.resolver.init_resolver(args)

    if core.config.init then
        local ok, err = core.config.init()
        if not ok then
            core.log.error("failed to load the configuration: ", err)
        end
    end

    xrpc.init()
end


function _M.stream_init_worker()
    core.log.info("enter stream_init_worker")
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx_now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)
    -- for testing only
    core.log.info("random stream test in [1, 10000]: ", math.random(1, 10000))

    if core.config.init_worker then
        local ok, err = core.config.init_worker()
        if not ok then
            core.log.error("failed to init worker process of ", core.config.type,
                           " config center, err: ", err)
        end
    end

    plugin.init_worker()
    xrpc.init_worker()
    router.stream_init_worker()
    apisix_upstream.init_worker()

    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events-stream", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end
    local discovery = require("apisix.discovery.init").discovery
    if discovery and discovery.init_worker then
        discovery.init_worker()
    end

    load_balancer = require("apisix.balancer")

    local_conf = core.config.local_conf()
end


function _M.stream_preread_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    ngx_ctx.api_ctx = api_ctx

    if not verify_tls_client(api_ctx) then
        return ngx_exit(1)
    end

    core.ctx.set_vars_meta(api_ctx)

    local ok, err = router.router_stream.match(api_ctx)
    if not ok then
        core.log.error(err)
        return ngx_exit(1)
    end

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local matched_route = api_ctx.matched_route
    if not matched_route then
        return ngx_exit(1)
    end


    local up_id = matched_route.value.upstream_id
    if up_id then
        local upstream = apisix_upstream.get_by_id(up_id)
        if not upstream then
            if is_http then
                return core.response.exit(502)
            end

            return ngx_exit(1)
        end

        api_ctx.matched_upstream = upstream

    else
        if matched_route.has_domain then
            local err
            matched_route, err = parse_domain_in_route(matched_route)
            if err then
                core.log.error("failed to get resolved route: ", err)
                return ngx_exit(1)
            end

            api_ctx.matched_route = matched_route
        end

        local route_val = matched_route.value
        api_ctx.matched_upstream = (matched_route.dns_value and
                                    matched_route.dns_value.upstream)
                                   or route_val.upstream
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.stream_filter(matched_route, plugins)
    -- core.log.info("valid plugins: ", core.json.delay_encode(plugins, true))

    api_ctx.conf_type = "stream/route"
    api_ctx.conf_version = matched_route.modifiedIndex
    api_ctx.conf_id = matched_route.value.id

    plugin.run_plugin("preread", plugins, api_ctx)

    if matched_route.value.protocol then
        xrpc.run_protocol(matched_route.value.protocol, api_ctx)
        return
    end

    local code, err = set_upstream(matched_route, api_ctx)
    if code then
        core.log.error("failed to set upstream: ", err)
        return ngx_exit(1)
    end

    local server, err = load_balancer.pick_server(matched_route, api_ctx)
    if not server then
        core.log.error("failed to pick server: ", err)
        return ngx_exit(1)
    end

    api_ctx.picked_server = server

    -- run the before_proxy method in preread phase first to avoid always reinit request
    common_phase("before_proxy")
end


function _M.stream_balancer_phase()
    core.log.info("enter stream_balancer_phase")
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return ngx_exit(1)
    end

    load_balancer.run(api_ctx.matched_route, api_ctx, common_phase)
end


function _M.stream_log_phase()
    core.log.info("enter stream_log_phase")

    local api_ctx = plugin.run_plugin("log")
    if not api_ctx then
        return
    end

    core.ctx.release_vars(api_ctx)
    if api_ctx.plugins then
        core.tablepool.release("plugins", api_ctx.plugins)
    end

    core.tablepool.release("api_ctx", api_ctx)
end


return _M
