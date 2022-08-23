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
local fetch_local_conf  = require("apisix.core.config_local").local_conf
local picker = require("apisix.balancer.least_conn")
local balancer = require("ngx.balancer")
local error = error
local ipairs = ipairs
local ngx = ngx
local ngx_shared = ngx.shared
local ngx_var = ngx.var
local tonumber = tonumber


local _M = {}
local servers = {}
local resolved_results = {}
local server_picker
local has_domain = false

local is_http = ngx.config.subsystem == "http"
local health_check_shm_name = "etcd-cluster-health-check"
if not is_http then
    health_check_shm_name = health_check_shm_name .. "-stream"
end
-- an endpoint is unhealthy if it is failed for HEALTH_CHECK_MAX_FAILURE times in
-- HEALTH_CHECK_DURATION_SECOND
local HEALTH_CHECK_MAX_FAILURE = 3
local HEALTH_CHECK_DURATION_SECOND = 10


local function create_resolved_result(server)
    local host, port = core.utils.parse_addr(server)
    return {
        host = host,
        port = port,
        server = server,
    }
end


function _M.init()
    local conf = fetch_local_conf()
    if not (conf.deployment and conf.deployment.etcd) then
        return
    end

    local etcd = conf.deployment.etcd
    if etcd.health_check_timeout then
        HEALTH_CHECK_DURATION_SECOND = etcd.health_check_timeout
    end

    for i, s in ipairs(etcd.host) do
        local _, to = core.string.find(s, "://")
        if not to then
            error("bad etcd endpoint format")
        end

        local addr = s:sub(to + 1)
        local host, _, err = core.utils.parse_addr(addr)
        if err then
            error("failed to parse host: ".. err)
        end

        resolved_results[i] = create_resolved_result(addr)
        servers[i] = addr

        if not core.utils.parse_ipv4(host) and not core.utils.parse_ipv6(host) then
            has_domain = true
            resolved_results[i].domain = host
        end
    end

    if #servers > 1 then
        local nodes = {}
        for _, s in ipairs(servers) do
            nodes[s] = 1
        end
        server_picker = picker.new(nodes, {})
    end
end


local function response_err(err)
    core.log.error("failure in conf server: ", err)

    if ngx.get_phase() == "balancer" then
        return
    end

    ngx.status = 503
    ngx.say(core.json.encode({error = err}))
    ngx.exit(0)
end


local function resolve_servers(ctx)
    if not has_domain then
        return
    end

    local changed = false
    for _, res in ipairs(resolved_results) do
        local domain = res.domain
        if not domain then
            goto CONTINUE
        end

        local ip, err = core.resolver.parse_domain(domain)
        if ip and res.host ~= ip then
            res.host = ip
            changed = true
            core.log.info(domain, " is resolved to: ", ip)
        end

        if err then
            core.log.error("dns resolver resolves domain: ", domain, " error: ", err)
        end

        ::CONTINUE::
    end

    if not changed then
        return
    end

    if #servers > 1 then
        local nodes = {}
        for _, res in ipairs(resolved_results) do
            local s = res.server
            nodes[s] = 1
        end
        server_picker = picker.new(nodes, {})
    end
end


local function gen_unhealthy_key(addr)
    return "conf_server:" .. addr
end


local function is_node_health(addr)
    local key = gen_unhealthy_key(addr)
    local count, err = ngx_shared[health_check_shm_name]:get(key)
    if err then
        core.log.warn("failed to get health check count, key: ", key, " err: ", err)
        return true
    end

    if not count then
        return true
    end

    return tonumber(count) < HEALTH_CHECK_MAX_FAILURE
end


local function report_failure(addr)
    local key = gen_unhealthy_key(addr)
    local count, err =
        ngx_shared[health_check_shm_name]:incr(key, 1, 0, HEALTH_CHECK_DURATION_SECOND)
    if not count then
        core.log.error("failed to report failure, key: ", key, " err: ", err)
    else
        -- count might be larger than HEALTH_CHECK_MAX_FAILURE
        core.log.warn("report failure, endpoint: ", addr, " count: ", count)
    end
end


local function pick_node_by_server_picker(ctx)
    local server, err = ctx.server_picker.get(ctx)
    if not server then
        err = err or "no valid upstream node"
        return nil, "failed to find valid upstream server: " .. err
    end

    ctx.balancer_server = server

    for _, r in ipairs(resolved_results) do
        if r.server == server then
            return r
        end
    end

    return nil, "unknown server: " .. server
end


local function pick_node(ctx)
    local res
    if server_picker then
        if not ctx.server_picker then
            ctx.server_picker = server_picker
        end

        local err
        res, err = pick_node_by_server_picker(ctx)
        if not res then
            return nil, err
        end

        while not is_node_health(res.server) do
            core.log.warn("endpoint ", res.server, " is unhealthy, skipped")

            if server_picker.after_balance then
                server_picker.after_balance(ctx, true)
            end

            res, err = pick_node_by_server_picker(ctx)
            if not res then
                return nil, err
            end
        end

    else
        -- we don't do health check if there is only one candidate
        res = resolved_results[1]
    end

    ctx.balancer_ip = res.host
    ctx.balancer_port = res.port

    ngx_var.upstream_host = res.domain or res.host
    if ngx.get_phase() == "balancer" then
        balancer.recreate_request()
    end

    return true
end


function _M.access()
    local ctx = ngx.ctx
    -- Nginx's DNS resolver doesn't support search option,
    -- so we have to use our own resolver
    resolve_servers(ctx)
    local ok, err = pick_node(ctx)
    if not ok then
        return response_err(err)
    end
end


function _M.balancer()
    local ctx = ngx.ctx
    if not ctx.balancer_run then
        ctx.balancer_run = true
        local retries = #servers - 1
        local ok, err = balancer.set_more_tries(retries)
        if not ok then
            core.log.error("could not set upstream retries: ", err)
        elseif err then
            core.log.warn("could not set upstream retries: ", err)
        end
    else
        if ctx.server_picker and ctx.server_picker.after_balance then
            ctx.server_picker.after_balance(ctx, true)
        end

        report_failure(ctx.balancer_server)

        local ok, err = pick_node(ctx)
        if not ok then
            return response_err(err)
        end
    end

    local ok, err = balancer.set_current_peer(ctx.balancer_ip, ctx.balancer_port)
    if not ok then
        return response_err(err)
    end
end


function _M.log()
    local ctx = ngx.ctx
    if ctx.server_picker and ctx.server_picker.after_balance then
        ctx.server_picker.after_balance(ctx, false)
    end
end


return _M
