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
local healthcheck = require("resty.healthcheck")
local roundrobin  = require("resty.roundrobin")
local resty_chash = require("resty.chash")
local balancer    = require("ngx.balancer")
local core        = require("apisix.core")
local error       = error
local str_char    = string.char
local str_gsub    = string.gsub
local pairs       = pairs
local tostring    = tostring
local set_more_tries   = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts     = balancer.set_timeouts
local upstreams_etcd


local module_name = "balancer"


local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})
local lrucache_checker = core.lrucache.new({
    ttl = 300, count = 256
})


local _M = {
    version = 0.1,
    name = module_name,
}


local function fetch_health_nodes(upstream, checker)
    if not checker then
        return upstream.nodes
    end

    local host = upstream.checks and upstream.checks.host
    local up_nodes = core.table.new(0, core.table.nkeys(upstream.nodes))

    for addr, weight in pairs(upstream.nodes) do
        local ip, port = core.utils.parse_addr(addr)
        local ok = checker:get_target_status(ip, port, host)
        if ok then
            up_nodes[addr] = weight
        end
    end

    if core.table.nkeys(up_nodes) == 0 then
        core.log.warn("all upstream nodes is unhealth, use default")
        up_nodes = upstream.nodes
    end

    return up_nodes
end


local function create_checker(upstream, healthcheck_parent)
    local checker = healthcheck.new({
        name = "upstream#" .. healthcheck_parent.key,
        shm_name = "upstream-healthcheck",
        checks = upstream.checks,
    })

    for addr, weight in pairs(upstream.nodes) do
        local ip, port = core.utils.parse_addr(addr)
        local ok, err = checker:add_target(ip, port, upstream.checks.host)
        if not ok then
            core.log.error("failed to add new health check target: ", addr,
                            " err: ", err)
        end
    end

    if upstream.parent then
        core.table.insert(upstream.parent.clean_handlers, function ()
            core.log.info("try to release checker: ", tostring(checker))
            checker:stop()
        end)

    else
        core.table.insert(healthcheck_parent.clean_handlers, function ()
            core.log.info("try to release checker: ", tostring(checker))
            checker:stop()
        end)
    end

    core.log.info("create new checker: ", tostring(checker))
    return checker
end


local function fetch_healthchecker(upstream, healthcheck_parent, version)
    if not upstream.checks then
        return
    end

    if upstream.checker then
        return
    end

    local checker = lrucache_checker(upstream, version,
                                     create_checker, upstream,
                                     healthcheck_parent)
    return checker
end


local function fetch_chash_hash_key(ctx, upstream)
    local key = upstream.key
    local hash_on = upstream.hash_on or "vars"
    local chash_key

    if hash_on == "consumer" then
        chash_key = ctx.consumer_id
    elseif hash_on == "vars" then
        chash_key = ctx.var[key]
    elseif hash_on == "header" then
        chash_key = ctx.var["http_" .. key]
    elseif hash_on == "cookie" then
        chash_key = ctx.var["cookie_" .. key]
    end

    if not chash_key then
        chash_key = ctx.var["remote_addr"]
        core.log.warn("chash_key fetch is nil, use default chash_key ",
                      "remote_addr: ", chash_key)
    end
    core.log.info("upstream key: ", key)
    core.log.info("hash_on: ", hash_on)
    core.log.info("chash_key: ", core.json.delay_encode(chash_key))

    return chash_key
end


local function create_server_picker(upstream, checker)
    if upstream.type == "roundrobin" then
        local up_nodes = fetch_health_nodes(upstream, checker)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))

        local picker = roundrobin:new(up_nodes)
        return {
            upstream = upstream,
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local up_nodes = fetch_health_nodes(upstream, checker)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))

        local str_null = str_char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(up_nodes) do
            local id = str_gsub(serv, ":", str_null)

            servers[id] = serv
            nodes[id] = weight
        end

        local picker = resty_chash:new(nodes)
        return {
            upstream = upstream,
            get = function (ctx)
                local chash_key = fetch_chash_hash_key(ctx, upstream)
                local id = picker:find(chash_key)
                -- core.log.warn("chash id: ", id, " val: ", servers[id])
                return servers[id]
            end
        }
    end

    return nil, "invalid balancer type: " .. upstream.type, 0
end


local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local healthcheck_parent = route
    local up_id = route.value.upstream_id
    local up_conf = (route.dns_value and route.dns_value.upstream)
                    or route.value.upstream
    if not up_id and not up_conf then
        return nil, nil, "missing upstream configuration"
    end

    local version
    local key

    if up_id then
        if not upstreams_etcd then
            return nil, nil, "need to create a etcd instance for fetching "
                             .. "upstream information"
        end

        local up_obj = upstreams_etcd:get(tostring(up_id))
        if not up_obj then
            return nil, nil, "failed to find upstream by id: " .. up_id
        end
        core.log.info("upstream: ", core.json.delay_encode(up_obj))

        healthcheck_parent = up_obj
        up_conf = up_obj.dns_value or up_obj.value
        version = up_obj.modifiedIndex
        key = up_conf.type .. "#upstream_" .. up_id

    else
        version = ctx.conf_version
        key = up_conf.type .. "#route_" .. route.value.id
    end

    if core.table.nkeys(up_conf.nodes) == 0 then
        return nil, nil, "no valid upstream node"
    end

    local checker = fetch_healthchecker(up_conf, healthcheck_parent, version)

    ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
    if checker and ctx.balancer_try_count > 1 then
        local state, code = get_last_failure()
        if state == "failed" then
            if code == 504 then
                checker:report_timeout(ctx.balancer_ip, ctx.balancer_port,
                                       up_conf.checks.host)
            else
                checker:report_tcp_failure(ctx.balancer_ip,
                    ctx.balancer_port, up_conf.checks.host)
            end

        else
            checker:report_http_status(ctx.balancer_ip, ctx.balancer_port,
                                       up_conf.checks.host, code)
        end
    end

    if ctx.balancer_try_count == 1 then
        local retries = up_conf.retries
        if retries and retries > 0 then
            set_more_tries(retries)
        else
            set_more_tries(core.table.nkeys(up_conf.nodes))
        end
    end

    if checker then
        version = version .. "#" .. checker.status_ver
    end

    local server_picker = lrucache_server_picker(key, version,
                            create_server_picker, up_conf, checker)
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end

    local server, err = server_picker.get(ctx)
    if not server then
        err = err or "no valid upstream node"
        return nil, nil, "failed to find valid upstream server, " .. err
    end

    if up_conf.timeout then
        local timeout = up_conf.timeout
        local ok, err = set_timeouts(timeout.connect, timeout.send,
                                     timeout.read)
        if not ok then
            core.log.error("could not set upstream timeouts: ", err)
        end
    end

    local ip, port, err = core.utils.parse_addr(server)
    ctx.balancer_ip = ip
    ctx.balancer_port = port

    return ip, port, err
end
-- for test
_M.pick_server = pick_server


function _M.run(route, ctx)
    local ip, port, err = pick_server(route, ctx)
    if err then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    local ok, err = balancer.set_current_peer(ip, port)
    if not ok then
        core.log.error("failed to set server peer [", ip, ":", port,
                       "] err: ", err)
        return core.response.exit(502)
    end

    ctx.proxy_passed = true
end


function _M.init_worker()
    local err
    upstreams_etcd, err = core.config.new("/upstreams", {
            automatic = true,
            item_schema = core.schema.upstream,
            filter = function(upstream)
                upstream.has_domain = false
                if not upstream.value then
                    return
                end

                for addr, _ in pairs(upstream.value.nodes or {}) do
                    local host = core.utils.parse_addr(addr)
                    if not core.utils.parse_ipv4(host) and
                       not core.utils.parse_ipv6(host) then
                        upstream.has_domain = true
                        break
                    end
                end

                core.log.info("filter upstream: ",
                              core.json.delay_encode(upstream))
            end,
        })
    if not upstreams_etcd then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
