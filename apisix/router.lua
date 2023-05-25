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
local http_route = require("apisix.http.route")
local apisix_upstream = require("apisix.upstream")
local core    = require("apisix.core")
local plugin_checker = require("apisix.plugin").plugin_checker
local str_lower = string.lower
local error   = error
local ipairs  = ipairs
local sub_str      = string.sub
local table        = require("apisix.core.table")
local json         = require("apisix.core.json")
local router_util = require("apisix.utils.router")
local tab_insert = table.insert

local _M = {version = 0.3}

local function empty_func() end

local function push_host_router(route, host_routes, only_uri_routes)
    if type(route) ~= "table" then
        return
    end

    local filter_fun, err
    if route.value.filter_func then
        filter_fun, err = loadstring(
                                "return " .. route.value.filter_func,
                                "router#" .. route.value.id)
        if not filter_fun then
            core.log.error("failed to load filter function: ", err,
                            " route id: ", route.value.id)
            return
        end

        filter_fun = filter_fun()
    end

    local hosts = route.value.hosts
    if not hosts then
        if route.value.host then
            hosts = {route.value.host}
        elseif route.value.service_id then
            local service = service_fetch(route.value.service_id)
            if not service then
                core.log.error("failed to fetch service configuration by ",
                                "id: ", route.value.service_id)
                -- we keep the behavior that missing service won't affect the route matching
            else
                hosts = service.value.hosts
            end
        end
    end

    local radixtree_route = {
        id = route.value.id,
        paths = route.value.uris or route.value.uri,
        methods = route.value.methods,
        priority = route.value.priority,
        remote_addrs = route.value.remote_addrs
                       or route.value.remote_addr,
        vars = route.value.vars,
        filter_fun = filter_fun,
        handler = function (api_ctx, match_opts)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
            api_ctx.curr_req_matched = match_opts.matched
            api_ctx.real_curr_req_matched_path = match_opts.matched._path
        end
    }

    if hosts == nil then
        core.table.insert(only_uri_routes, radixtree_route)
        return
    end

    for i, host in ipairs(hosts) do
        local host_rev = host:reverse()
        if not host_routes[host_rev] then
            host_routes[host_rev] = {radixtree_route}
        else
            tab_insert(host_routes[host_rev], radixtree_route)
        end
    end
end

local function filter(route, pre_route_obj, size)
    route.orig_modifiedIndex = route.modifiedIndex
    route.update_count = 0

    route.has_domain = false
    if route.value then
        if route.value.host then
            route.value.host = str_lower(route.value.host)
        elseif route.value.hosts then
            for i, v in ipairs(route.value.hosts) do
                route.value.hosts[i] = str_lower(v)
            end
        end

        apisix_upstream.filter_upstream(route.value.upstream, route)
    end

    core.log.info("filter route: ", core.json.delay_encode(route, true))

    --load_full_data()'s filter() goes here. create radixtree while etcd compacts
    local router_opts = {
        no_param_match = true
    }
    local conf = core.config.local_conf()
    if conf.apisix.router.http == "radixtree_uri" then
        if size then
            if size == #pre_route_obj.values then
                local uri_routes = {}
                local uri_router = http_route.create_radixtree_uri_router(pre_route_obj.values, uri_routes, false)
                if not uri_router then
                    error("create radixtree in init worker phase failed.", #pre_route_obj.values)
                    return
                end

                _M.uri_router = uri_router
            end

            return
        end

        --only sync_data()'s filter() goes here
        local router_module = require("apisix.router")
        local routes_obj = router_module.router_http.user_routes
        local radixtree_obj = router_module.uri_router

        local cur_route
        if route.value then
            local status = table.try_read_attr(route, "value", "status")
            if status and status == 0 then
                return
            end

            local filter_fun, err
            if route.value.filter_func then
                filter_fun, err = loadstring(
                    "return " .. route.value.filter_func,
                    "router#" .. route.value.id
                )
                if not filter_fun then
                    core.log.error("failed to load filter function: ", err, " route id", route.value.id)
                    return
                end

                filter_fun = filter_fun()
            end

            cur_route = {
                id = route.value.id,
                paths = route.value.uris or route.value.uri,
                methods = route.value.methods,
                priority = route.value.priority,
                hosts = route.value.hosts or route.value.host,
                remote_addrs = route.value.remote_addrs or route.value.remote_addr,
                vars = route.value.vars,
                filter_fun = filter_fun,
                handler = function(api_ctx, match_opts)
                    api_ctx.matched_params = nil
                    api_ctx.matched_route = route
                    api_ctx.curr_req_matched = match_opts.matched
                end
            }
        end

        local err
        if pre_route_obj then
            local last_route = {
                id = pre_route_obj.value.id,
                paths = pre_route_obj.value.uris or pre_route_obj.value.uri,
                methods = pre_route_obj.value.methods,
                priority = pre_route_obj.value.priority,
                hosts = pre_route_obj.value.hosts or pre_route_obj.value.host,
                remote_addrs = pre_route_obj.value.remote_addrs or pre_route_obj.value.remote_addr,
                vars = pre_route_obj.value.vars
            }
        
            if route.value then
                --update route
                core.log.notice("update routes watched from etcd into radixtree.", json.encode(route))
                err = radixtree_obj:update_route(last_route, cur_route, router_opts)
                if err ~= nil then
                    core.log.error("update a route into radixtree failed.", json.encode(route), err)
                    return
                end
            else
                --delete route
                core.log.notice("delete routes watched from etcd into radixtree.", json.encode(route))
                err = radixtree_obj:delete_route(last_route, router_opts)
                if err ~= nil then
                    core.log.error("delete a route into radixtree failed.", json.encode(route), err)
                    return
                end
            end
        elseif route.value then
            --create route
            core.log.notice("create routes watched from etcd into radixtree.", json.encode(route))
            err = radixtree_obj:add_route(cur_route, router_opts)
            if err ~= nil then
                core.log.error("add routes into radixtree failed.", json.encode(route), err)
                return
            end
        else
            core.log.error("invalid operation type for a route.", route.key)
            return
        end
    elseif conf.apisix.router.http == "radixtree_host_uri" then
        local host_uri = require("apisix.http.router.radixtree_host_uri")
        if size then
            if size == #pre_route_obj.values then
                host_uri.create_radixtree_router(pre_route_obj.values)
            end
    
            return
        end

        local only_uri_routes = {}
        local host_router_routes = {}
        if route.value then
            local host_routes = {}
            local status = core.table.try_read_attr(route, "value", "status")
            -- check the status
            if not status or status == 1 then
                push_host_router(route, host_routes, only_uri_routes)
            end

            for host_rev, routes in pairs(host_routes) do
                local sub_router = router_util.new(routes)

                core.table.insert(host_router_routes, {
                    id = route.value.id,
                    paths = host_rev,
                    filter_fun = function(vars, opts, ...)
                        return sub_router:dispatch(vars.uri, opts, ...)
                    end,
                    handler = empty_func,
                })
            end
        end

        if pre_route_obj then
            local pre_host_routes = {}
            local pre_only_uri_routes = {}
            local pre_host_router_routes = {}
            local pre_status = core.table.try_read_attr(pre_route_obj, "value", "status")
            -- check the status
            if not pre_status or pre_status == 1 then
                push_host_router(pre_route_obj, pre_host_routes, pre_only_uri_routes)
            end

            for host_rev, routes in pairs(pre_host_routes) do
                local sub_router = router_util.new(routes)

                core.table.insert(pre_host_router_routes, {
                    id = pre_route_obj.value.id,
                    paths = host_rev,
                    filter_fun = function(vars, opts, ...)
                        return sub_router:dispatch(vars.uri, opts, ...)
                    end,
                    handler = empty_func,
                })
            end
        
            if route.value then
                --update route
                core.log.notice("update routes watched from etcd into radixtree.", json.encode(route))
                for _, pre_r_opt in ipairs(pre_host_router_routes) do
                    for _, r_opt in ipairs(host_router_routes) do
                        host_uri.host_router:update_route(pre_r_opt, r_opt, router_opts)
                    end
                end 
            else
                --delete route
                core.log.notice("delete routes watched from etcd into radixtree.", json.encode(route))
                for _, r_opt in ipairs(pre_host_router_routes) do
                    host_uri.host_router:delete_route(r_opt, router_opts)
                end
            end
        elseif route.value then
            --create route
            core.log.notice("create routes watched from etcd into radixtree.", json.encode(route))
           
            if #host_router_routes > 0 then
                for _, r_opt in ipairs(host_router_routes) do
                    host_uri.host_router:add_route(r_opt)
                end
            end

            -- create router: only_uri_router
            if #only_uri_routes > 0 then
                for _, r_opt in ipairs(only_uri_routes) do
                    host_uri.only_uri_router:add_route(r_opt)
                end
            end
        end
    end
end


-- attach common methods if the router doesn't provide its custom implementation
local function attach_http_router_common_methods(http_router)
    if http_router.routes == nil then
        http_router.routes = function ()
            if not http_router.user_routes then
                return nil, nil
            end

            local user_routes = http_router.user_routes
            return user_routes.values, user_routes.conf_version
        end
    end

    if http_router.init_worker == nil then
        http_router.init_worker = function (filter)
            http_router.user_routes = http_route.init_worker(filter)
        end
    end
end

function _M.http_init_worker()
    local conf = core.config.local_conf()
    local router_http_name = "radixtree_uri"
    local router_ssl_name = "radixtree_sni"

    if conf and conf.apisix and conf.apisix.router then
        router_http_name = conf.apisix.router.http or router_http_name
        router_ssl_name = conf.apisix.router.ssl or router_ssl_name
    end

    local router_http = require("apisix.http.router." .. router_http_name)
    attach_http_router_common_methods(router_http)
    router_http.init_worker(filter)
    _M.router_http = router_http

    local router_ssl = require("apisix.ssl.router." .. router_ssl_name)
    router_ssl.init_worker()
    _M.router_ssl = router_ssl

    _M.api = require("apisix.api_router")

    local global_rules, err = core.config.new("/global_rules", {
            automatic = true,
            item_schema = core.schema.global_rule,
            checker = plugin_checker,
        })
    if not global_rules then
        error("failed to create etcd instance for fetching /global_rules : "
              .. err)
    end
    _M.global_rules = global_rules
end


function _M.stream_init_worker()
    local router_ssl_name = "radixtree_sni"

    local router_stream = require("apisix.stream.router.ip_port")
    router_stream.stream_init_worker(filter)
    _M.router_stream = router_stream

    local router_ssl = require("apisix.ssl.router." .. router_ssl_name)
    router_ssl.init_worker()
    _M.router_ssl = router_ssl
end


function _M.ssls()
    return _M.router_ssl.ssls()
end

function _M.http_routes()
    if not _M.router_http then
        return nil, nil
    end
    return _M.router_http.routes()
end

function _M.stream_routes()
    -- maybe it's not inited.
    if not _M.router_stream then
        return nil, nil
    end
    return _M.router_stream.routes()
end


-- for test
_M.filter_test = filter


return _M
