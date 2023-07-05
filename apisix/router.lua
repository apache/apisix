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
local core = require("apisix.core")
local json = require("apisix.core.json")
local plugin_checker = require("apisix.plugin").plugin_checker
local str_lower = string.lower
local error = error
local ipairs = ipairs
local sub_str = string.sub


local _M = {version = 0.3}

_M.need_create_radixtree = true


local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end


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

    if not obj then
        return
    end
    --save sync route and operation type into a map
    if type(pre_route_or_size) == "number" then
        if pre_route_or_size == #obj.values then
            _M.need_create_radixtree = true
        end
        return
    end

    local key
    if obj.single_item then
        key = obj.key
    else
        key = short_key(obj, route.key)
    end

    local sync_tb = _M.sync_tb
    if pre_route_or_size then
        if route.value then
            --update route
            core.log.notice("update routes watched from etcd into radixtree.", json.encode(route))
            if not sync_tb[route.value.id] then
                sync_tb[route.value.id] = {op = "update", last_route = pre_route_or_size, cur_route = route}
            elseif sync_tb[route.value.id]["op"] == "update" then
                sync_tb[route.value.id] = {op = "update", last_route = sync_tb[route.value.id]["last_route"],
                                            cur_route = route}
            elseif sync_tb[route.value.id]["op"] == "create" then
                sync_tb[route.value.id] = {op = "create", cur_route = route}
            end
        else
            --delete route
            core.log.notice("delete routes watched from etcd into radixtree.", json.encode(route))
            if not sync_tb[key] then
                sync_tb[key] = {op = "delete", last_route = pre_route_or_size}
            elseif sync_tb[key]["op"] == "create" then
                sync_tb[key] = nil
            elseif sync_tb[key]["op"] == "update" then
                sync_tb[key] = {op = "delete", last_route = sync_tb[key]["last_route"]}
            end
        end
    elseif route.value then
        --create route
        core.log.notice("create routes watched from etcd into radixtree.", json.encode(route))
        if not sync_tb[route.value.id] then
            sync_tb[route.value.id] = {op = "create", cur_route = route}
        elseif sync_tb[route.value.id]["op"] == "delete" then
            sync_tb[route.value.id] = {op = "update", cur_route = route, 
                                        last_route = sync_tb[route.value.id]["last_route"]}
        end
    else
        core.log.error("invalid operation type for a route.", route.key)
        return
    end

    _M.sync_tb = sync_tb
    core.log.info("filter route: ", core.json.delay_encode(route, true))
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
    _M.sync_tb = {}
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
