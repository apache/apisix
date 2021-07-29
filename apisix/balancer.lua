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
local require           = require
local balancer          = require("ngx.balancer")
local core              = require("apisix.core")
local priority_balancer = require("apisix.balancer.priority")
local ipairs            = ipairs
local enable_keepalive = balancer.enable_keepalive
local set_more_tries   = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts     = balancer.set_timeouts
local ngx_now          = ngx.now


local module_name = "balancer"
local pickers = {}

local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})
local lrucache_addr = core.lrucache.new({
    ttl = 300, count = 1024 * 4
})


local _M = {
    version = 0.2,
    name = module_name,
}


local function transform_node(new_nodes, node)
    if not new_nodes._priority_index then
        new_nodes._priority_index = {}
    end

    if not new_nodes[node.priority] then
        new_nodes[node.priority] = {}
        core.table.insert(new_nodes._priority_index, node.priority)
    end

    new_nodes[node.priority][node.host .. ":" .. node.port] = node.weight
    return new_nodes
end


local function fetch_health_nodes(upstream, checker)
    local nodes = upstream.nodes
    if not checker then
        local new_nodes = core.table.new(0, #nodes)
        for _, node in ipairs(nodes) do
            new_nodes = transform_node(new_nodes, node)
        end
        return new_nodes
    end

    local host = upstream.checks and upstream.checks.active and upstream.checks.active.host
    local port = upstream.checks and upstream.checks.active and upstream.checks.active.port
    local up_nodes = core.table.new(0, #nodes)
    for _, node in ipairs(nodes) do
        local ok, err = checker:get_target_status(node.host, port or node.port, host)
        if ok then
            up_nodes = transform_node(up_nodes, node)
        elseif err then
            core.log.error("failed to get health check target status, addr: ",
                node.host, ":", port or node.port, ", host: ", host, ", err: ", err)
        end
    end

    if core.table.nkeys(up_nodes) == 0 then
        core.log.warn("all upstream nodes is unhealthy, use default")
        for _, node in ipairs(nodes) do
            up_nodes = transform_node(up_nodes, node)
        end
    end

    return up_nodes
end


local function create_server_picker(upstream, checker)
    local picker = pickers[upstream.type]
    if not picker then
        pickers[upstream.type] = require("apisix.balancer." .. upstream.type)
        picker = pickers[upstream.type]
    end

    if picker then
        local nodes = upstream.nodes
        local addr_to_domain = {}
        for _, node in ipairs(nodes) do
            if node.domain then
                local addr = node.host .. ":" .. node.port
                addr_to_domain[addr] = node.domain
            end
        end

        local up_nodes = fetch_health_nodes(upstream, checker)

        if #up_nodes._priority_index > 1 then
            core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))
            local server_picker = priority_balancer.new(up_nodes, upstream, picker)
            server_picker.addr_to_domain = addr_to_domain
            return server_picker
        end

        core.log.info("upstream nodes: ",
                      core.json.delay_encode(up_nodes[up_nodes._priority_index[1]]))
        local server_picker = picker.new(up_nodes[up_nodes._priority_index[1]], upstream)
        server_picker.addr_to_domain = addr_to_domain
        return server_picker
    end

    return nil, "invalid balancer type: " .. upstream.type, 0
end


local function parse_addr(addr)
    local host, port, err = core.utils.parse_addr(addr)
    return {host = host, port = port}, err
end


-- set_balancer_opts will be called in balancer phase and before any tries
local function set_balancer_opts(route, ctx)
    local up_conf = ctx.upstream_conf

    -- If the matched route has timeout config, prefer to use the route config.
    local timeout = nil
    if route and route.value and route.value.timeout then
        timeout = route.value.timeout
    else
        if up_conf.timeout then
            timeout = up_conf.timeout
        end
    end
    if timeout then
        local ok, err = set_timeouts(timeout.connect, timeout.send,
                                     timeout.read)
        if not ok then
            core.log.error("could not set upstream timeouts: ", err)
        end
    end

    local retries = up_conf.retries
    if not retries or retries < 0 then
        retries = #up_conf.nodes - 1
    end

    if retries > 0 then
        if up_conf.retry_timeout and up_conf.retry_timeout > 0 then
            ctx.proxy_retry_deadline = ngx_now() + up_conf.retry_timeout
        end
        local ok, err = set_more_tries(retries)
        if not ok then
            core.log.error("could not set upstream retries: ", err)
        elseif err then
            core.log.warn("could not set upstream retries: ", err)
        end
    end
end


-- pick_server will be called:
-- 1. in the access phase so that we can set headers according to the picked server
-- 2. each time we need to retry upstream
local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local up_conf = ctx.upstream_conf

    local nodes_count = #up_conf.nodes
    if nodes_count == 1 then
        local node = up_conf.nodes[1]
        ctx.balancer_ip = node.host
        ctx.balancer_port = node.port
        return node
    end

    local version = ctx.upstream_version
    local key = ctx.upstream_key
    local checker = ctx.up_checker

    ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
    if ctx.balancer_try_count > 1 then
        if ctx.server_picker and ctx.server_picker.after_balance then
            ctx.server_picker.after_balance(ctx, true)
        end

        if checker then
            local state, code = get_last_failure()
            local host = up_conf.checks and up_conf.checks.active and up_conf.checks.active.host
            local port = up_conf.checks and up_conf.checks.active and up_conf.checks.active.port
            if state == "failed" then
                if code == 504 then
                    checker:report_timeout(ctx.balancer_ip, port or ctx.balancer_port, host)
                else
                    checker:report_tcp_failure(ctx.balancer_ip, port or ctx.balancer_port, host)
                end
            else
                checker:report_http_status(ctx.balancer_ip, port or ctx.balancer_port, host, code)
            end
        end
    end

    if checker then
        version = version .. "#" .. checker.status_ver
    end

    -- the same picker will be used in the whole request, especially during the retry
    local server_picker = ctx.server_picker
    if not server_picker then
        server_picker = lrucache_server_picker(key, version,
                                               create_server_picker, up_conf, checker)
    end
    if not server_picker then
        return nil, "failed to fetch server picker"
    end

    local server, err = server_picker.get(ctx)
    if not server then
        err = err or "no valid upstream node"
        return nil, "failed to find valid upstream server, " .. err
    end
    ctx.balancer_server = server

    local domain = server_picker.addr_to_domain[server]
    local res, err = lrucache_addr(server, nil, parse_addr, server)
    if err then
        core.log.error("failed to parse server addr: ", server, " err: ", err)
        return core.response.exit(502)
    end

    res.domain = domain
    ctx.balancer_ip = res.host
    ctx.balancer_port = res.port
    ctx.server_picker = server_picker

    return res
end


-- for test
_M.pick_server = pick_server


local set_current_peer
do
    local pool_opt = {}

    function set_current_peer(server, ctx)
        local up_conf = ctx.upstream_conf
        local keepalive_pool = up_conf.keepalive_pool

        if keepalive_pool and enable_keepalive then
            local idle_timeout = keepalive_pool.idle_timeout
            local size = keepalive_pool.size
            local requests = keepalive_pool.requests

            pool_opt.pool_size = size
            local ok, err = balancer.set_current_peer(server.host, server.port,
                                                      pool_opt)
            if not ok then
                return ok, err
            end

            return balancer.enable_keepalive(idle_timeout, requests)
        end

        return balancer.set_current_peer(server.host, server.port)
    end
end


function _M.run(route, ctx, plugin_funcs)
    local server, err

    if ctx.picked_server then
        -- use the server picked in the access phase
        server = ctx.picked_server
        ctx.picked_server = nil

        set_balancer_opts(route, ctx)

    else
        if ctx.proxy_retry_deadline and ctx.proxy_retry_deadline < ngx_now() then
            -- retry count is (try count - 1)
            core.log.error("proxy retry timeout, retry count: ", (ctx.balancer_try_count or 1) - 1,
                           ", deadline: ", ctx.proxy_retry_deadline, " now: ", ngx_now())
            return core.response.exit(502)
        end
        -- retry
        server, err = pick_server(route, ctx)
        if not server then
            core.log.error("failed to pick server: ", err)
            return core.response.exit(502)
        end

        local header_changed
        local pass_host = ctx.pass_host
        if pass_host == "node" and balancer.recreate_request then
            local host = server.domain or server.host
            if host ~= ctx.var.upstream_host then
                -- retried node has a different host
                ctx.var.upstream_host = host
                header_changed = true
            end
        end

        local _, run = plugin_funcs("balancer")
        -- always recreate request as the request may be changed by plugins
        if (run or header_changed) and balancer.recreate_request then
            balancer.recreate_request()
        end
    end

    core.log.info("proxy request to ", server.host, ":", server.port)

    local ok, err = set_current_peer(server, ctx)
    if not ok then
        core.log.error("failed to set server peer [", server.host, ":",
                       server.port, "] err: ", err)
        return core.response.exit(502)
    end

    ctx.proxy_passed = true
end


function _M.init_worker()
end

return _M
