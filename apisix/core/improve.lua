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

local route_lrucache = core.lrucache.new({
    count = 512
})

local enable_route_cache

local _M = {}

local orig_router_match
local router

local function match_route(ctx)
    orig_router_match(ctx)
    -- replace the router match
    return ctx.matched_route or false
end


local function ai_match(ctx)
    local route_ckey = ctx.var.uri .. "-" .. ctx.var.method .. "-" ..
                       ctx.var.host .. "-" .. ctx.var.remote_addr
    local ver = router.user_routes.conf_version
    local route_cache = route_lrucache(route_ckey, ver,
                        match_route, ctx)
    -- if the version has not changed, use the cached route
    if route_cache then
        ctx.matched_route = route_cache
    end
end


function  _M.routes_analyze(routes)
    local vars_flag = false
    local filter_flag = false
    local prefix_match_flag = false

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            if route.vars then
                vars_flag = true
                break
            end

            if route.filter_fun then
                filter_flag = true
                break
            end

            if route.uri and core.string.has_suffix(route.uri, "*") then
                prefix_match_flag = true
                break
            end

            if route.uris then
                for _, uri in ipairs(route.uris) do
                    if core.string.has_suffix(uri, "*") then
                        prefix_match_flag = true
                        break
                    end
                end
            end
        end
    end

    if vars_flag or filter_flag or prefix_match_flag then
        enable_route_cache = false
        router.match = orig_router_match
    else
        enable_route_cache = true
        router.match = ai_match
    end
end


function _M.enable_route_cache()
    return enable_route_cache
end


function _M.init_worker(router_http)
    router = router_http
    orig_router_match = router.match
end

return _M
