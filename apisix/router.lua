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
local event = require("apisix.core.event")


local _M = {version = 0.3}

local function empty_func() end
local routes_obj, first_route

local function filter(route, pre_route_or_size, obj)
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
    --filter route from other config source
    if not obj then
        return
    end

    --load_full_data()'s filter() goes here. create radixtree while etcd compacts
    local router_module = require("apisix.router")
    local conf = core.config.local_conf()
    if conf.apisix.router.http == "radixtree_uri" or conf.apisix.router.http == "radixtree_uri_with_parameter" then
        local router_opts
        local with_parameter = false
        if conf.apisix.router.http == "radixtree_uri" then
            router_opts = {
                no_param_match = true
            }
        else
            with_parameter = true
            router_opts = {
                no_param_match = false
            }
        end

        if type(pre_route_or_size) == "number" then
            if pre_route_or_size == #obj.values then
                routes_obj = obj
                local uri_routes = {}
                core.log.notice("create radixtree uri after load_full_data.", #routes_obj.values)
                local uri_router = http_route.create_radixtree_uri_router(routes_obj.values, uri_routes, with_parameter)
                if not uri_router then
                    core.log.error("create radixtree in init worker phase failed.", #routes_obj.values)
                    return
                end

                _M.uri_router = uri_router
                if not first_route then
                    first_route = true
                end
            end

            return
        end

        if not first_route then
            routes_obj = obj
            local uri_routes = {}
            core.log.notice("create radixtree uri for the first route income.")
            local uri_router = http_route.create_radixtree_uri_router(routes_obj.values, uri_routes, with_parameter)
            if not uri_router then
                core.log.error("create radixtree in init worker phase failed.", #routes_obj.values)
                return
            end

            _M.uri_router = uri_router
            first_route = true
            return
        end

        --only sync_data()'s filter() goes here
        if router_module.router_http then
            event.push(event.CONST.BUILD_ROUTER, routes_obj.values)
        end

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
        if pre_route_or_size then
            local last_route = {
                id = pre_route_or_size.value.id,
                paths = pre_route_or_size.value.uris or pre_route_or_size.value.uri,
                methods = pre_route_or_size.value.methods,
                priority = pre_route_or_size.value.priority,
                hosts = pre_route_or_size.value.hosts or pre_route_or_size.value.host,
                remote_addrs = pre_route_or_size.value.remote_addrs or pre_route_or_size.value.remote_addr,
                vars = pre_route_or_size.value.vars
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
        local router_opts = {
            no_param_match = true
        }

        local host_uri = require("apisix.http.router.radixtree_host_uri")
        if type(pre_route_or_size) == "number" then
            if pre_route_or_size == #obj.values then
                routes_obj = obj
                core.log.notice("create radixtree uri after load_full_data.", #routes_obj.values)
                host_uri.create_radixtree_router(routes_obj.values)
                if not first_route then
                    first_route = true
                end
            end

            return
        end

        if not first_route then
            routes_obj = obj
            core.log.notice("create radixtree uri for the first route income.")
            host_uri.create_radixtree_router(routes_obj.values)
            first_route = true
            return
        end

        if router_module.router_http then
            event.push(event.CONST.BUILD_ROUTER, routes_obj.values)
        end

        local only_uri_routes = {}
        local route_opt, pre_route_opt = {}, {}
        local all_hosts = {}
        local hosts, pre_hosts = nil, nil
        local rdx_r = {}
        local pre_rdx_r = {}
        local op = {add={}, upd={}, del={}}


        local status = table.try_read_attr(route, "value", "status")
        if status and status == 0 then
            return
        end

        host_uri.push_host_router(route, host_uri.host_routes, only_uri_routes, all_hosts, op, rdx_r, pre_route_or_size, pre_rdx_r)

        hosts = all_hosts["host"]
        if hosts ~= nil then
            for _, h in ipairs(hosts) do
                local host_rev = h:reverse()
                local routes = host_uri.host_routes[host_rev]
                local sub_router = router_util.new(routes)
                route_opt[host_rev] = {
                    id = 1,
                    paths = host_rev,
                    filter_fun = function(vars, opts, ...)
                        return sub_router:dispatch(vars.uri, opts, ...)
                    end,
                    handler = empty_func,
                }
            end
        end

        pre_hosts = all_hosts["pre_host"]
        if pre_hosts ~= nil then
            for _, h in ipairs(pre_hosts) do
                local host_rev = h:reverse()
                pre_route_opt[host_rev] = {
                    id = 1,
                    paths = host_rev,
                    filter_fun = empty_func,
                    handler = empty_func,
                }
            end
        end

        for k, v in pairs(op) do
            if k == "add" then
                for _, j in ipairs(v) do
                    core.log.notice("add the route with reverse host watched from etcd into radixtree.", json.encode(route), j)
                    local r_opt = route_opt[j]
                    host_uri.host_router:add_route(r_opt, router_opts)
                end
            elseif k == "upd" then
                for _, j in ipairs(v) do
                    core.log.notice("update the route with reverse host watched from etcd into radixtree.", json.encode(route), j)
                    local r_opt = route_opt[j]
                    host_uri.host_router:update_route(r_opt, r_opt, router_opts)
                end
            elseif k == "del" then
                for _, j in ipairs(v) do
                    core.log.notice("delete the route with reverse host watched from etcd into radixtree.", json.encode(route), j)
                    local pre_r_opt = pre_route_opt[j]
                    host_uri.host_router:delete_route(pre_r_opt, router_opts)
                end
            end
        end

        if (route.value and not hosts) and (not pre_route_or_size or pre_hosts) then
            core.log.notice("add the route with uri watched from etcd into radixtree.", json.encode(route))
            host_uri.only_uri_router:add_route(rdx_r, router_opts)
        elseif (route.value and not hosts) and (pre_route_or_size and not pre_hosts) then
            core.log.notice("update the route with uri watched from etcd into radixtree.", json.encode(route))
            host_uri.only_uri_router:update_route(pre_rdx_r, rdx_r, router_opts)
        elseif (pre_route_or_size and not pre_hosts) and (not route.value or hosts) then
            core.log.notice("delete the route with uri watched from etcd into radixtree.", json.encode(pre_route_or_size))
            host_uri.only_uri_router:delete_route(pre_rdx_r, router_opts)
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
    event.push(event.CONST.BUILD_ROUTER, router_http.user_routes.values)

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
