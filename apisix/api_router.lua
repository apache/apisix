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
local plugin_mod = require("apisix.plugin")
local ip_restriction = require("apisix.plugins.ip-restriction")
local core = require("apisix.core")
local ipairs = ipairs
local type = type


local _M = {}
local match_opts = {}
local has_route_not_under_apisix
local interceptors = {
    ["ip-restriction"] = {
        run = function (conf, ctx)
            return ip_restriction.access(conf, ctx)
        end,
        schema = ip_restriction.schema,
    }
}


_M.interceptors_schema = {
    ["$comment"] = "this is the mark for our interceptors schema",
    type = "array",
    items = {
        type = "object",
        minItems = 1,
        properties = {
            name = {
                type = "string",
                enum = {"ip-restriction"},
            },
            conf = {
                type = "object",
            }
        },
        required = {"name", "conf"},
        dependencies = {
            name = {
                oneOf = {}
            }
        }
    }
}
for name, attrs in pairs(interceptors) do
    core.table.insert(_M.interceptors_schema.items.properties.name.enum, name)
    core.table.insert(_M.interceptors_schema.items.dependencies.name.oneOf, {
        properties = {
            name = {
                enum = {name},
            },
            conf = attrs.schema,
        }
    })
end


local fetch_api_router
do
    local routes = {}
function fetch_api_router()
    core.table.clear(routes)

    has_route_not_under_apisix = false

    for _, plugin in ipairs(plugin_mod.plugins) do
        local api_fun = plugin.api
        if api_fun then
            local name = plugin.name
            local api_routes = api_fun()
            core.log.debug("fetched api routes: ",
                           core.json.delay_encode(api_routes, true))
            for _, route in ipairs(api_routes) do
                local typ_uri = type(route.uri)
                if typ_uri == "string" then
                    has_route_not_under_apisix =
                        not core.string.has_prefix(route.uri, "/apisix/")
                else
                    for _, uri in ipairs(route.uri) do
                        if not core.string.has_prefix(route.uri, "/apisix/") then
                            has_route_not_under_apisix = true
                        end
                    end
                end

                core.table.insert(routes, {
                        methods = route.methods,
                        paths = route.uri,
                        handler = function (api_ctx)
                            local code, body

                            local metadata = plugin_mod.plugin_metadata(name)
                            if metadata and metadata.value.interceptors then
                                for _, rule in ipairs(metadata.value.interceptors) do
                                    local f = interceptors[rule.name]
                                    if f == nil then
                                        core.log.error("unknown interceptor: ", rule.name)
                                    else
                                        code, body = f.run(rule.conf, api_ctx)
                                        if code or body then
                                            return core.response.exit(code, body)
                                        end
                                    end
                                end
                            end

                            code, body = route.handler(api_ctx)
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


function _M.has_route_not_under_apisix()
    if has_route_not_under_apisix == nil then
        return true
    end

    return has_route_not_under_apisix
end


function _M.match(api_ctx)
    local api_router = core.lrucache.global("api_router", plugin_mod.load_times, fetch_api_router)
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
