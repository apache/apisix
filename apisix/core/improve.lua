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
local core            = require("apisix.core")
local ipairs          = ipairs
local type            = type

local recovery_func = core.lrucache.new({
    count = 512
})

local route_lrucache = core.lrucache.new({
    count = 512
})

local enable_route_cache

local _M = {}

local ori_router_match
local router

local route_ckey
local route_cver

local radix_tree_changed

function _M.router_match(ctx)
    -- TODO: generate cache key dynamically according to the user routes
    route_ckey = ctx.var.uri .. "-" .. ctx.var.method .. "-" ..
                 ctx.var.host .. "-" .. ctx.var.remote_addr
    route_cver = router.user_routes.conf_version
    recovery_func(route_ckey, route_cver, function()
        -- if the version has changed, fall back to the original router match
        router.match = ori_router_match
        return true
    end)
end


local function create_router_cache(ctx)
    -- replace the router match
    router.match = function()
        -- do nothing
        core.log.info("hit route cache, key: ", route_ckey)
    end
    return ctx.matched_route
end


function _M.router_match_post(ctx)
    if not enable_route_cache then
        return
    end

    local route_cache = route_lrucache(route_ckey, route_cver,
                                       create_router_cache, ctx)
    -- if the version has not changed, use the cached route
    if route_cache and not ctx.matched_route then
        ctx.matched_route = route_cache
    end
end


function  _M.routes_analyze(routes)
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            if route.value.vars then
                enable_route_cache = false
                return
            end

            if route.value.filter_fun then
                enable_route_cache = false
                return
            end

            if route.value.priority and route.value.priority ~= 0 then
                enable_route_cache = false
                return
            end

            if route.value.uri and core.string.has_suffix(route.value.uri, "*") then
                enable_route_cache = false
                return
            end

            if route.value.uris then
                for _, uri in ipairs(route.value.uris) do
                    if core.string.has_suffix(uri, "*") then
                        enable_route_cache = false
                        return
                    end
                end
            end
        end
    end
    enable_route_cache = true
end


function _M.enable_route_cache()
    return enable_route_cache
end


function _M.init_worker(router_http)
    router = router_http
    ori_router_match = router.match
end

return _M
