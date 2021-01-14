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
local core = require("apisix.core")
local discovery = require("apisix.discovery.init").discovery
local error = error
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local upstreams
local healthcheck


local lrucache_checker = core.lrucache.new({
    ttl = 300, count = 256
})


local _M = {}


local function set_directly(ctx, key, ver, conf)
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

    ctx.upstream_conf = conf
    ctx.upstream_version = ver
    ctx.upstream_key = key
    ctx.upstream_healthcheck_parent = conf.parent
    return
end
_M.set = set_directly


local function create_checker(upstream)
    if healthcheck == nil then
        healthcheck = require("resty.healthcheck")
    end

    local healthcheck_parent = upstream.parent
    local checker, err = healthcheck.new({
        name = "upstream#" .. healthcheck_parent.key,
        shm_name = "upstream-healthcheck",
        checks = upstream.checks,
    })

    if not checker then
        core.log.error("fail to create healthcheck instance: ", err)
        return nil
    end

    local host = upstream.checks and upstream.checks.active and upstream.checks.active.host
    local port = upstream.checks and upstream.checks.active and upstream.checks.active.port
    for _, node in ipairs(upstream.nodes) do
        local ok, err = checker:add_target(node.host, port or node.port, host)
        if not ok then
            core.log.error("failed to add new health check target: ", node.host, ":",
                    port or node.port, " err: ", err)
        end
    end

    core.table.insert(healthcheck_parent.clean_handlers, function ()
        core.log.info("try to release checker: ", tostring(checker))
        checker:clear()
        checker:stop()
    end)

    core.log.info("create new checker: ", tostring(checker))
    return checker
end


local function fetch_healthchecker(upstream, version)
    if not upstream.checks then
        return
    end

    if upstream.checker then
        return
    end

    local checker = lrucache_checker(upstream, version,
                                     create_checker, upstream)
    return checker
end


function _M.set_by_route(route, api_ctx)
    if api_ctx.upstream_conf then
        core.log.warn("upstream node has been specified, ",
                      "cannot be set repeatedly")
        return
    end

    local up_conf = api_ctx.matched_upstream
    if not up_conf then
        return 500, "missing upstream configuration in Route or Service"
    end
    -- core.log.info("up_conf: ", core.json.delay_encode(up_conf, true))

    if up_conf.service_name then
        if not discovery then
            return 500, "discovery is uninitialized"
        end
        if not up_conf.discovery_type then
            return 500, "discovery server need appoint"
        end

        local dis = discovery[up_conf.discovery_type]
        if not dis then
            return 500, "discovery " .. up_conf.discovery_type .. "is uninitialized"
        end
        up_conf.nodes = dis.nodes(up_conf.service_name)
    end

    set_directly(api_ctx, up_conf.type .. "#upstream_" .. tostring(up_conf),
                 api_ctx.conf_version, up_conf)

    local nodes_count = up_conf.nodes and #up_conf.nodes or 0
    if nodes_count == 0 then
        return 502, "no valid upstream node"
    end

    if nodes_count > 1 then
        local checker = fetch_healthchecker(up_conf, api_ctx.upstream_version)
        api_ctx.up_checker = checker
    end

    return
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

                upstream.value.parent = upstream
                core.log.info("filter upstream: ", core.json.delay_encode(upstream))
            end,
        })
    if not upstreams then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
