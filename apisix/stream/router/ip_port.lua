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
local core      = require("apisix.core")
local core_ip  = require("apisix.core.ip")
local config_util = require("apisix.core.config_util")
local stream_plugin_checker = require("apisix.plugin").stream_plugin_checker
local router_new = require("apisix.utils.router").new
local apisix_ssl = require("apisix.ssl")
local xrpc = require("apisix.stream.xrpc")
local error     = error
local tonumber  = tonumber
local ipairs = ipairs

local user_routes
local router_ver
local tls_router
local other_routes = {}
local _M = {version = 0.1}



local function match_addrs(route, vars)
    -- todo: use resty-ipmatcher to support multiple ip address
    if route.value.remote_addr then
        local ok, _ = route.value.remote_addr_matcher:match(vars.remote_addr)
        if not ok then
            return false
        end
    end

    if route.value.server_addr then
        local ok, _ = route.value.server_addr_matcher:match(vars.server_addr)
        if not ok then
            return false
        end
    end

    -- todo: use resty-ipmatcher to support multiple ip address
    if route.value.server_port and
       route.value.server_port ~= tonumber(vars.server_port) then
        return false
    end

    return true
end


local create_router
do
    local sni_to_items = {}
    local tls_routes = {}

    function create_router(items)
        local tls_routes_idx = 1
        local other_routes_idx = 1
        core.table.clear(tls_routes)
        core.table.clear(other_routes)
        core.table.clear(sni_to_items)

        for _, item in config_util.iterate_values(items) do
            if item.value == nil then
                goto CONTINUE
            end

            local route = item.value
            if route.protocol and route.protocol.superior_id then
                -- subordinate route won't be matched in the entry
                -- TODO: check the subordinate relationship in the Admin API
                goto CONTINUE
            end

            if item.value.remote_addr then
                item.value.remote_addr_matcher = core_ip.create_ip_matcher({item.value.remote_addr})
            end
            if item.value.server_addr then
                item.value.server_addr_matcher = core_ip.create_ip_matcher({item.value.server_addr})
            end
            if not route.sni then
                other_routes[other_routes_idx] = item
                other_routes_idx = other_routes_idx + 1
                goto CONTINUE
            end

            local sni_rev = route.sni:reverse()
            local stored = sni_to_items[sni_rev]
            if stored then
                core.table.insert(stored, item)
                goto CONTINUE
            end

            sni_to_items[sni_rev] = {item}
            tls_routes[tls_routes_idx] = {
                paths = sni_rev,
                filter_fun = function (vars, opts, ctx)
                    local items = sni_to_items[sni_rev]
                    for _, route in ipairs(items) do
                        local hit = match_addrs(route, vars)
                        if hit then
                            ctx.matched_route = route
                            return true
                        end
                    end
                    return false
                end,
                handler = function (ctx, sni_rev)
                    -- done in the filter_fun
                end
            }
            tls_routes_idx = tls_routes_idx + 1

            ::CONTINUE::
        end

        if #tls_routes > 0 then
            local router, err = router_new(tls_routes)
            if not router then
                return err
            end

            tls_router = router
        end

        return nil
    end
end


do
    local match_opts = {}

    function _M.match(api_ctx)
        if router_ver ~= user_routes.conf_version then
            local err = create_router(user_routes.values)
            if err then
                return false, "failed to create router: " .. err
            end

            router_ver = user_routes.conf_version
        end

        local sni = apisix_ssl.server_name()
        if sni and tls_router then
            local sni_rev = sni:reverse()

            core.table.clear(match_opts)
            match_opts.vars = api_ctx.var

            local _, err = tls_router:dispatch(sni_rev, match_opts, api_ctx)
            if err then
                return false, "failed to match TLS router: " .. err
            end
        end

        if api_ctx.matched_route then
            -- unlike the matcher for the SSL, it is fine to let
            -- '*.x.com' to match 'a.b.x.com' as we don't care about
            -- the certificate
            return true
        end

        for _, route in ipairs(other_routes) do
            local hit = match_addrs(route, api_ctx.var)
            if hit then
                api_ctx.matched_route = route
                return true
            end
        end

        core.log.info("not hit any route")
        return true
    end
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end

local function stream_route_checker(item, in_cp)
    if item.plugins then
        local ok, message = stream_plugin_checker(item, in_cp)
        if not ok then
            return false, message
        end
    end
    -- validate the address format when remote_address or server_address is not nil
    if item.remote_addr then
        if not core_ip.validate_cidr_or_ip(item.remote_addr) then
            return false, "invalid remote_addr: " .. item.remote_addr
        end
    end
    if item.server_addr then
        if not core_ip.validate_cidr_or_ip(item.server_addr) then
            return false, "invalid server_addr: " .. item.server_addr
        end
    end

    if item.protocol then
        local prot_conf = item.protocol
        if prot_conf then
            local ok, message = xrpc.check_schema(prot_conf, false)
            if not ok then
                return false, message
            end
        end
    end

    return true
end
_M.stream_route_checker = stream_route_checker


function _M.stream_init_worker(filter)
    local err
    user_routes, err = core.config.new("/stream_routes", {
            automatic = true,
            item_schema = core.schema.stream_route,
            checker = stream_route_checker,
            filter = filter,
        })

    if not user_routes then
        error("failed to create etcd instance for fetching /stream_routes : "
              .. err)
    end
end


return _M
