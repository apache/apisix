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
local ipairs = ipairs
local type = type
local tab_insert = table.insert
local loadstring = loadstring
local pairs = pairs
local ar = require("apisix.router")
local cached_router_version
local cached_service_version
local host_router
local only_uri_router


local _M = {version = 0.1}


local function get_host_radixtree_route(host_rev, sub_router)
    return {
        id = host_rev,
        paths = host_rev,
        sub_router = sub_router,
        filter_fun = function(vars, opts, ...)
            return sub_router:dispatch(vars.uri, opts, ...)
        end,
        handler = function (api_ctx, match_opts)
            api_ctx.real_curr_req_matched_host = match_opts.matched._path
        end
    }
end


local function push_host_router(route, host_routes, only_uri_routes, mode)
    if route == nil or (type(route) ~= "table" or  route.value == nil) then
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


local function create_radixtree_router(routes)
    local host_routes = {}
    local only_uri_routes = {}
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
        core.table.insert(host_router_routes, get_host_radixtree_route(host_rev, sub_router))
    end

    event.push(event.CONST.BUILD_ROUTER, routes)

    -- create router: host_router
    host_router = router.new(host_router_routes)

    -- create router: only_uri_router
    only_uri_router = router.new(only_uri_routes)
    return true
end


local function add_route(host_rev, route, router_opts)
    local err
    local sub_router = host_router:get_sub_router(host_rev, host_rev, router_opts)

    if sub_router then
        err = sub_router:add_route(route, router_opts)

        if err ~= nil then
            core.log.error("add route in radixtree sub_router failed. ",
                            core.json.delay_encode(route), err)
            return
        end
    else
        local new_sub_router = router.new({route})
        local host_radix_tree = get_host_radixtree_route(host_rev, new_sub_router)
        err = host_router:add_route(host_radix_tree, router_opts)
        if err ~= nil then
            core.log.error("add route in host radixtree failed. ",
                            core.json.delay_encode(route), err)
            return
        end
    end
end


local function delete_route(host_rev, route, router_opts)
    local err
    local sub_router = host_router:get_sub_router(host_rev, host_rev, router_opts)
    err = sub_router:delete_route(route, router_opts)

    if err ~= nil then
        core.log.error("delete route in radixtree sub_router failed. ",
                        core.json.delay_encode(route), err)
        return
    end

    local is_empty = sub_router:isempty()

    if is_empty then
        err = host_router:delete_route(get_host_radixtree_route(host_rev, nil), router_opts)

        if err ~= nil then
            core.log.error("delete route in host radixtree failed. ",
                            core.json.delay_encode(route), err)
            return
        end
    end
end


local function modify_route(host_rev, last_route, route, router_opts)
    local sub_router = host_router:get_sub_router(host_rev, host_rev, router_opts)
    local err = sub_router:update_route(last_route, route, router_opts)
    if err ~= nil then
        core.log.error("update route in radixtree sub_router failed. ",
                        core.json.delay_encode(route), err)
        return
    end
end


local function update_routes(last_host_routes, host_routes, router_opts)
    local pre_t = {}
    local t = {}

    for host_rev, _ in pairs(last_host_routes) do
        pre_t[host_rev] = 1
    end

    for host_rev, _ in pairs(host_routes) do
        t[host_rev] = 1
    end

    local common = {}
    for k in pairs(pre_t) do
        if t[k] then
            core.table.insert(common, k)
        end
    end

    for _, p in ipairs(common) do
        modify_route(p, last_host_routes[p], host_routes[p], router_opts)
        pre_t[p] = nil
        t[p] = nil
    end


    for p in pairs(pre_t) do
        delete_route(p, last_host_routes[p], router_opts)
    end


    for p in pairs(t) do
        add_route(p, host_routes[p], router_opts)
    end

end


local function flat_routes(host_routes, only_uri_routes)
    for host_rev, routes in pairs(host_routes) do
        host_routes[host_rev] = routes[1]
    end

    return host_routes, only_uri_routes and only_uri_routes[1]
end


local function incremental_operate_radixtree(routes)
    if ar.need_create_radixtree then
        core.log.notice("create object of radixtree host uri after load_full_data or init. ",
                        #routes)
        create_radixtree_router(routes)
        ar.need_create_radixtree = false
        core.table.clear(ar.sync_tb)
        return
    end

    local op, cur_route, last_route
    local router_opts = {
        no_param_match = true
    }

    event.push(event.CONST.BUILD_ROUTER, routes)
    for k, _ in pairs(ar.sync_tb) do
        op = ar.sync_tb[k]["op"]
        cur_route = ar.sync_tb[k]["cur_route"]
        last_route = ar.sync_tb[k]["last_route"]
        local err
        local host_routes = {}
        local only_uri_routes = {}
        local last_host_routes = {}
        local last_only_uri_routes = {}

        push_host_router(cur_route, host_routes, only_uri_routes)
        push_host_router(last_route, last_host_routes, last_only_uri_routes)

        local host_routes, only_uri_route = flat_routes(host_routes, only_uri_routes)
        local last_host_routes, last_only_uri_route =
            flat_routes(last_host_routes, last_only_uri_routes)

        if not core.table.isempty(host_routes) or not core.table.isempty(last_host_routes) then
            if op == "update" then
                core.log.notice("update routes watched from etcd into radixtree.")
                update_routes(last_host_routes, host_routes, router_opts)
            elseif op == "create" then
                core.log.notice("create routes watched from etcd into radixtree.")
                for host_rev, route in pairs(host_routes) do
                    add_route(host_rev, route, router_opts)
                end
            elseif op == "delete" then
                core.log.notice("delete routes watched from etcd into radixtree.")
                for host_rev, route in pairs(last_host_routes) do
                    delete_route(host_rev, route, router_opts)
                end
            end
        else
            if op == "update" then
                err = only_uri_router:update_route(last_only_uri_route, only_uri_route, router_opts)

                if err ~= nil then
                    core.log.error("update a in into radixtree failed. ",
                                    core.json.delay_encode(only_uri_route), err)
                    return
                end
            elseif op == "create" then
                err = only_uri_router:add_route(only_uri_route, router_opts)
                if err ~= nil then
                    core.log.error("add route in radixtree failed. ",
                                    core.json.delay_encode(only_uri_route), err)
                    return
                end
            elseif op == "delete" then
                err = only_uri_router:delete_route(last_only_uri_route, router_opts)
                if err ~= nil then
                    core.log.error("delete route in radixtree failed. ",
                                    core.json.delay_encode(last_only_uri_route), err)
                    return
                end
            end
        end
        ar.sync_tb[k] = nil
    end
end


function _M.match(api_ctx)
    local user_routes = _M.user_routes
    local _, service_version = get_services()
    if not cached_router_version or cached_router_version ~= user_routes.conf_version
        or not cached_service_version or cached_service_version ~= service_version
    then
        incremental_operate_radixtree(user_routes.values)
        cached_router_version = user_routes.conf_version
        cached_service_version = service_version
    end

    return _M.matching(api_ctx)
end


function _M.matching(api_ctx)
    core.log.info("route match mode: radixtree_host_uri")

    local match_opts = core.tablepool.fetch("route_match_opts", 0, 16)
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
            core.tablepool.release("route_match_opts", match_opts)
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx, match_opts)
    core.tablepool.release("route_match_opts", match_opts)
    return ok
end


return _M
