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

local core = require("apisix.core")
local error = error
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local upstreams


local _M = {}


local function set_directly(ctx, key, ver, conf, parent)
    if not ctx then
        error("missing argument ctx", 2)
    end
    if not key then
        error("missing argument key", 2)
    end
    if not ver then
        error("missing argument ver", 2)
    end
    if not conf then
        error("missing argument conf", 2)
    end
    if not parent then
        error("missing argument parent", 2)
    end

    ctx.upstream_conf = conf
    ctx.upstream_version = ver
    ctx.upstream_key = key
    ctx.upstream_healthcheck_parent = parent
    return
end
_M.set = set_directly


function _M.set_by_route(route, api_ctx)
    if api_ctx.upstream_conf then
        core.log.warn("upstream node has been specified, ",
                      "cannot be set repeatedly")
        return true
    end

    local up_conf = api_ctx.matched_upstream
    if not up_conf then
        return false, "missing upstream configuration in Route or Service"
    end
    -- core.log.info("up_conf: ", core.json.delay_encode(up_conf, true))

    set_directly(api_ctx, up_conf.type .. "#upstream_" .. tostring(up_conf),
                 api_ctx.conf_version, up_conf, route)
    return true
end


function _M.upstreams()
    if not upstreams then
        return nil, nil
    end

    return upstreams.values, upstreams.conf_version
end


function _M.check_schema(conf)
    return core.schema.check(core.schema.upstream, conf)
end


function _M.init_worker()
    local err
    upstreams, err = core.config.new("/upstreams", {
            automatic = true,
            item_schema = core.schema.upstream,
            filter = function(upstream)
                upstream.has_domain = false
                if not upstream.value or not upstream.value.nodes then
                    return
                end

                local nodes = upstream.value.nodes
                if core.table.isarray(nodes) then
                    for _, node in ipairs(nodes) do
                        local host = node.host
                        if not core.utils.parse_ipv4(host) and
                                not core.utils.parse_ipv6(host) then
                            upstream.has_domain = true
                            break
                        end
                    end
                else
                    local new_nodes = core.table.new(core.table.nkeys(nodes), 0)
                    for addr, weight in pairs(nodes) do
                        local host, port = core.utils.parse_addr(addr)
                        if not core.utils.parse_ipv4(host) and
                                not core.utils.parse_ipv6(host) then
                            upstream.has_domain = true
                        end
                        local node = {
                            host = host,
                            port = port,
                            weight = weight,
                        }
                        core.table.insert(new_nodes, node)
                    end
                    upstream.value.nodes = new_nodes
                end

                core.log.info("filter upstream: ", core.json.delay_encode(upstream))
            end,
        })
    if not upstreams then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
