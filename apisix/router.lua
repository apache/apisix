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
local base_router = require("apisix.http.router.base")
local core    = require("apisix.core")
local plugin_checker = require("apisix.plugin").plugin_checker
local error   = error
local pairs   = pairs
local ipairs  = ipairs


local _M = {version = 0.3}


local function filter(route)
    route.has_domain = false
    if not route.value then
        return
    end

    if not route.value.upstream or not route.value.upstream.nodes then
        return
    end

    local nodes = route.value.upstream.nodes
    if core.table.isarray(nodes) then
        for _, node in ipairs(nodes) do
            local host = node.host
            if not core.utils.parse_ipv4(host) and
                    not core.utils.parse_ipv6(host) then
                route.has_domain = true
                break
            end
        end
    else
        local new_nodes = core.table.new(core.table.nkeys(nodes), 0)
        for addr, weight in pairs(nodes) do
            local host, port = core.utils.parse_addr(addr)
            if not core.utils.parse_ipv4(host) and
                    not core.utils.parse_ipv6(host) then
                route.has_domain = true
            end
            local node = {
                host = host,
                port = port,
                weight = weight,
            }
            core.table.insert(new_nodes, node)
        end
        route.value.upstream.nodes = new_nodes
    end

    core.log.info("filter route: ", core.json.delay_encode(route))
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
            http_router.user_routes = base_router.init_worker(filter)
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
    local router_stream = require("apisix.stream.router.ip_port")
    router_stream.stream_init_worker(filter)
    _M.router_stream = router_stream
end


function _M.ssls()
    return _M.router_ssl.ssls()
end

function _M.http_routes()
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
