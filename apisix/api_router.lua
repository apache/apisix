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
local plugin = require("apisix.plugin")
local core = require("apisix.core")
local ipairs = ipairs


local _M = {}
local match_opts = {}


local fetch_api_router
do
    local routes = {}
function fetch_api_router()
    core.table.clear(routes)

    for _, plugin in ipairs(plugin.plugins) do
        local api_fun = plugin.api
        if api_fun then
            local api_routes = api_fun()
            core.log.debug("fetched api routes: ",
                           core.json.delay_encode(api_routes, true))
            for _, route in ipairs(api_routes) do
                core.table.insert(routes, {
                        methods = route.methods,
                        paths = route.uri,
                        handler = function (...)
                            local code, body = route.handler(...)
                            if code or body then
                                core.response.exit(code, body)
                            end
                        end
                    })
            end
        end
    end

    return router.new(routes)
end

end -- do


function _M.match(api_ctx)
    local api_router = core.lrucache.global("api_router", plugin.load_times, fetch_api_router)
    if not api_router then
        core.log.error("failed to fetch valid api router")
        return false
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.request_method

    local ok = api_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    return ok
end


return _M
