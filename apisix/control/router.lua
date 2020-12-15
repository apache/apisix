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
local router = require("resty.radixtree")
local v1_routes = require("apisix.control.v1")
local plugin_mod = require("apisix.plugin")
local core = require("apisix.core")
local str_sub = string.sub
local ipairs = ipairs
local type = type
local ngx = ngx
local get_method = ngx.req.get_method


local _M = {}
local current_version = 1


local fetch_control_api_router
do
    local function register_api_routes(routes, api_routes)
        for _, route in ipairs(api_routes) do
            core.table.insert(routes, {
                methods = route.methods,
                paths = route.uri,
                handler = function (api_ctx)
                    local code, body = route.handler(api_ctx)
                    if code or body then
                        if type(body) == "table" and ngx.header["Content-Type"] == nil then
                            core.response.set_header("Content-Type", "application/json")
                        end

                        core.response.exit(code, body)
                    end
                end
            })
        end
    end

    local routes = {}

function fetch_control_api_router()
    core.table.clear(routes)

    register_api_routes(routes, v1_routes)

    for _, plugin in ipairs(plugin_mod.plugins) do
        local api_fun = plugin.control_api
        if api_fun then
            local api_routes = api_fun(current_version)
            register_api_routes(routes, api_routes)
        end
    end

    return router.new(routes)
end

end -- do


do
    local match_opts = {}
    local cached_version
    local router

function _M.match(uri)
    if not core.string.has_prefix(uri, "/v1/") then
        -- we will support different versions in the future
        return false
    end

    if cached_version ~= plugin_mod.load_times then
        router = fetch_control_api_router()
        if router == nil then
            core.log.error("failed to fetch valid api router")
            return false
        end

        cached_version = plugin_mod.load_times
    end

    core.table.clear(match_opts)
    match_opts.method = get_method()

    uri = str_sub(uri, #"/v1" + 1)
    local ok = router:dispatch(uri, match_opts)
    return ok
end

end -- do


return _M
