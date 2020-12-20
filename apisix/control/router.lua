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
local builtin_v1_routes = require("apisix.control.v1")
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
                -- note that it is 'uris' for control API, which is an array of strings
                paths = route.uris,
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
    local v1_routes = {}
    local function empty_func() end

function fetch_control_api_router()
    core.table.clear(v1_routes)

    register_api_routes(v1_routes, builtin_v1_routes)

    for _, plugin in ipairs(plugin_mod.plugins) do
        local api_fun = plugin.control_api
        if api_fun then
            local api_routes = api_fun(current_version)
            register_api_routes(v1_routes, api_routes)
        end
    end

    local v1_router, err = router.new(v1_routes)
    if not v1_router then
        return nil, err
    end

    core.table.clear(routes)
    core.table.insert(routes, {
        paths = {"/v1/*"},
        filter_fun = function(vars, opts, ...)
            local uri = str_sub(vars.uri, #"/v1" + 1)
            return v1_router:dispatch(uri, opts, ...)
        end,
        handler = empty_func,
    })

    return router.new(routes)
end

end -- do


do
    local match_opts = {}
    local cached_version
    local router

function _M.match(uri)
    if cached_version ~= plugin_mod.load_times then
        local err
        router, err = fetch_control_api_router()
        if router == nil then
            core.log.error("failed to fetch valid api router: ", err)
            return false
        end

        cached_version = plugin_mod.load_times
    end

    core.table.clear(match_opts)
    match_opts.method = get_method()

    return router:dispatch(uri, match_opts)
end

end -- do


return _M
