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

local route_lrucache = core.lrucache.new({
    -- TODO: we need to set the cache size by count of routes
    -- if we have done this feature, we need to release the origin lrucache
    count = 512
})

local _M = {}

local orig_router_match
local router

local function match_route(ctx)
    orig_router_match(ctx)
    return ctx.matched_route or false
end


local function ai_match(ctx)
    -- TODO: we need to generate cache key dynamically
    local key = ctx.var.uri .. "-" .. ctx.var.method .. "-" .. ctx.var.host
    local ver = router.user_routes.conf_version
    local route_cache = route_lrucache(key, ver,
                                       match_route, ctx)
    -- if the version has not changed, use the cached route
    if route_cache then
        ctx.matched_route = route_cache
    end
end


function  _M.routes_analyze(routes)
    -- TODO: we need to add a option in config.yaml to enable this feature(default is true)
    local route_flags = core.table.new(0, 2)
    for _, route in ipairs(routes) do
        if route.vars then
            route_flags["vars"] = true
        end

        if route.filter_fun then
            route_flags["filter_fun"] = true
        end

        if route.remote_addr or route.remote_addrs then
            route_flags["remote_addr"] = true
        end
    end

    if route_flags["vars"] or route_flags["filter_fun"]
         or route_flags["remote_addr"] then
        router.match = orig_router_match
    else
        core.log.info("use ai plane to match route")
        router.match = ai_match
    end
end


function _M.init_worker(router_http)
    router = router_http
    orig_router_match = router.match
end

return _M
