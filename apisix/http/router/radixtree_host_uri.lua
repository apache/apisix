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
local router = require("apisix.utils.router")
local core = require("apisix.core")
local event = require("apisix.core.event")
local get_services = require("apisix.http.service").services
local service_fetch = require("apisix.http.service").get
local apisix_router = require("apisix.router")
local table = require("apisix.core.table")
local json = require("apisix.core.json")
local ipairs = ipairs
local type = type
local tab_insert = table.insert
local loadstring = loadstring
local pairs = pairs
local cached_router_version
local cached_service_version
local host_router
local only_uri_router
local host_routes = {}
local only_uri_routes = {}


local _M = {version = 0.1}


local function empty_func() end
local function push_host_router(route, host_routes, only_uri_routes, all_hosts, op, rdx_rt, pre_route, pre_rdx_rt)
    if type(route) ~= "table" then
        return
    end

    local filter_fun, err
    if route.value and route.value.filter_func then
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

    local radixtree_route, pre_radixtree_route = {}, {}
    local hosts
    if route and route.value then
        hosts = route.value.hosts
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

        radixtree_route = {
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

        if rdx_rt ~= nil then
            for k, v in pairs(radixtree_route) do
                rdx_rt[k] = v
            end
        end
    end

    if hosts == nil and all_hosts == nil then
        core.table.insert(only_uri_routes, radixtree_route)
        return
    end

    local pre_hosts
    if pre_route and pre_route.value then
        pre_hosts = pre_route.value.hosts
        if not pre_hosts then
            if pre_route.value.host then
                pre_hosts = {pre_route.value.host}
            elseif pre_route.value.service_id then
                local service = service_fetch(pre_route.value.service_id)
                if not service then
                    core.log.error("failed to fetch service configuration by ",
                                    "id: ", pre_route.value.service_id)
                    -- we keep the behavior that missing service won't affect the route matching
                else
                    pre_hosts = service.value.hosts
                end
            end
        end

        pre_radixtree_route = {
            id = pre_route.value.id,
            paths = pre_route.value.uris or pre_route.value.uri,
            methods = pre_route.value.methods,
            priority = pre_route.value.priority,
            remote_addrs = pre_route.value.remote_addrs
                           or pre_route.value.remote_addr,
            vars = pre_route.value.vars,
            filter_fun = filter_fun,
            handler = function (api_ctx, match_opts)
                api_ctx.matched_params = nil
                api_ctx.matched_route = pre_route
                api_ctx.curr_req_matched = match_opts.matched
                api_ctx.real_curr_req_matched_path = match_opts.matched._path
            end
        }

        if pre_rdx_rt ~= nil then
            for k, v in pairs(pre_radixtree_route) do
                pre_rdx_rt[k] = v
            end
        end
    end

    if all_hosts ~= nil then
        all_hosts["host"] = hosts
        all_hosts["pre_host"] = pre_hosts
    end

    local pre_t = {}
    if pre_hosts then
        for i, h in ipairs(pre_hosts) do
            local rev_h = h:reverse()
            pre_t[rev_h] = 1
        end
    end

    local t = {}
    if hosts then
        for i, h in ipairs(hosts) do
            local rev_h = h:reverse()
            t[rev_h] = 1
        end
    end

    local comm = {}
    for k, v in pairs(pre_t) do
        if t[k] ~= nil then
            tab_insert(comm, k)
            pre_t[k] = nil
            t[k] = nil
        end
    end

    for _, j in ipairs(comm) do
        local routes = host_routes[j]
        if routes == nil then
            core.log.error("no routes array for reverse host in the map.", j)
            return
        end

        local found = false
        for i, r in ipairs(routes) do
            if r.id == radixtree_route.id then
                routes[i] = radixtree_route
                found = true
                if op then
                    table.insert(op["upd"], j)
                end
                break
            end
        end

        if not found then
            core.log.error("cannot find the route in common host's table.", j, radixtree_route.id)
            return
        end
    end

    for k, v in pairs(pre_t) do
        local routes = host_routes[k]
        if routes == nil then
            core.log.error("no routes array for reverse host in the map.", k)
            return
        end

        local found = false
        for i, r in ipairs(routes) do
            if r.id == pre_radixtree_route.id then
                table.remove(routes, i)
                found = true
                break
            end
        end

        if not found then
            core.log.error("cannot find the route in previous host's table.", k, pre_radixtree_route.id)
            return
        end

        if #routes == 0 then
            host_routes[k] = nil
            if op then
                table.insert(op["del"], k)
            end
        else
            if op then
                table.insert(op["upd"], k)
            end
        end
    end

    for k, v in pairs(t) do
        local routes = host_routes[k]
        if routes == nil then
            host_routes[k] = {radixtree_route}
            if op then
                table.insert(op["add"], k)
            end
        else
            table.insert(routes, radixtree_route)
            if op then
                table.insert(op["upd"], k)
            end
        end
    end
end


local function create_radixtree_router(routes)
    host_router = nil
    routes = routes or {}

    for _, route in ipairs(routes) do
        local status = core.table.try_read_attr(route, "value", "status")
        -- check the status
        if not status or status == 1 then
            push_host_router(route, host_routes, only_uri_routes)
        end
    end

    -- create router: host_router
    local host_router_routes = {}
    for host_rev, routes in pairs(host_routes) do
        local sub_router = router.new(routes)

        core.table.insert(host_router_routes, {
            paths = host_rev,
            filter_fun = function(vars, opts, ...)
                return sub_router:dispatch(vars.uri, opts, ...)
            end,
            handler = function (api_ctx, match_opts)
                api_ctx.real_curr_req_matched_host = match_opts.matched._path
            end
        })
    end

    event.push(event.CONST.BUILD_ROUTER, routes)

    if #host_router_routes > 0 then
        host_router = router.new(host_router_routes)
    end

    -- create router: only_uri_router
    only_uri_router = router.new(only_uri_routes)
    return true
end


local function incremental_operate_radixtree(routes)
    if apisix_router.need_create_radixtree then
        core.log.notice("create radixtree uri after load_full_data.", #routes)
        create_radixtree_router(routes)
        apisix_router.need_create_radixtree = false
        return
    end

    local sync_tb = apisix_router.sync_tb
    local op, route, last_route, err
    local router_opts = {
        no_param_match = true
    }

    event.push(event.CONST.BUILD_ROUTER, routes)
    for k, _ in pairs(sync_tb) do
        op = sync_tb[k]["op"]
        route = sync_tb[k]["cur_route"]
        last_route = sync_tb[k]["last_route"]

        if route then
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

            push_host_router(route, host_routes, only_uri_routes, all_hosts, op, rdx_r, last_route, pre_rdx_r)

            hosts = all_hosts["host"]
            if hosts ~= nil then
                for _, h in ipairs(hosts) do
                    local host_rev = h:reverse()
                    local routes = host_routes[host_rev]
                    local sub_router = router.new(routes)
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
                        host_router:add_route(r_opt, router_opts)
                    end
                elseif k == "upd" then
                    for _, j in ipairs(v) do
                        core.log.notice("update the route with reverse host watched from etcd into radixtree.", json.encode(route), j)
                        local r_opt = route_opt[j]
                        host_router:update_route(r_opt, r_opt, router_opts)
                    end
                elseif k == "del" then
                    for _, j in ipairs(v) do
                        core.log.notice("delete the route with reverse host watched from etcd into radixtree.", json.encode(route), j)
                        local pre_r_opt = pre_route_opt[j]
                        host_router:delete_route(pre_r_opt, router_opts)
                    end
                end
            end

            if (route.value and not hosts) and (not last_route or pre_hosts) then
                core.log.notice("add the route with uri watched from etcd into radixtree.", json.encode(route))
                only_uri_router:add_route(rdx_r, router_opts)
            elseif (route.value and not hosts) and (last_route and not pre_hosts) then
                core.log.notice("update the route with uri watched from etcd into radixtree.", json.encode(route))
                only_uri_router:update_route(pre_rdx_r, rdx_r, router_opts)
            elseif (last_route and not pre_hosts) and (not route.value or hosts) then
                core.log.notice("delete the route with uri watched from etcd into radixtree.", json.encode(last_route))
                only_uri_router:delete_route(pre_rdx_r, router_opts)
            end
        end

        sync_tb[k] = nil
    end

    apisix_router.sync_tb = sync_tb
end


    local match_opts = {}
function _M.match(api_ctx)
    local user_routes = _M.user_routes
    local _, service_version = get_services()
    if not cached_router_version or cached_router_version ~= user_routes.conf_version
        or not cached_service_version or cached_service_version ~= service_version
    then
        --create_radixtree_router(user_routes.values)
        incremental_operate_radixtree(user_routes.values)
        cached_router_version = user_routes.conf_version
        cached_service_version = service_version
    end

    return _M.matching(api_ctx)
end


function _M.matching(api_ctx)
    core.log.info("route match mode: radixtree_host_uri")

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.request_method
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var
    match_opts.host = api_ctx.var.host
    match_opts.matched = core.tablepool.fetch("matched_route_record", 0, 4)

    if host_router then
        local host_uri = api_ctx.var.host
        local ok = host_router:dispatch(host_uri:reverse(), match_opts, api_ctx, match_opts)
        if ok then
            if api_ctx.real_curr_req_matched_path then
                api_ctx.curr_req_matched._path = api_ctx.real_curr_req_matched_path
                api_ctx.real_curr_req_matched_path = nil
            end
            if api_ctx.real_curr_req_matched_host then
                api_ctx.curr_req_matched._host = api_ctx.real_curr_req_matched_host:reverse()
                api_ctx.real_curr_req_matched_host = nil
            end
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx, match_opts)
    return ok
end


return _M
