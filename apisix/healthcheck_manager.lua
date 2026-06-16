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
local ipairs   = ipairs
local pcall   = pcall
local exiting      = ngx.worker.exiting
local pairs    = pairs
local tostring = tostring
local core = require("apisix.core")
local config_local   = require("apisix.core.config_local")
local resource = require("apisix.resource")
local upstream_utils = require("apisix.utils.upstream")
local healthcheck
local tab_clone = core.table.clone
local timer_every = ngx.timer.every
local jp = require("jsonpath")
local config_util = require("apisix.core.config_util")

local _M = {}
local working_pool = {}     -- resource_path -> {version, checker, checks,
                            --                   pass_host, upstream_host, targets_map}
local waiting_pool = {}      -- resource_path -> resource_ver

local DELAYED_CLEAR_TIMEOUT = 10
local healthcheck_shdict_name = "upstream-healthcheck"


local function get_healthchecker_name(value)
    return "upstream#" .. (value.resource_key or value.upstream.resource_key)
end
_M.get_healthchecker_name = get_healthchecker_name


local function is_ip(host)
    return core.utils.parse_ipv4(host) or core.utils.parse_ipv6(host)
end


-- A health checker must only be managed once the upstream nodes have been
-- resolved to concrete IPs, because that is exactly what the balancer queries
-- the checker with (see balancer.lua `fetch_health_nodes`). If we built or
-- diffed targets from an unresolved snapshot (domain hosts, e.g. right after a
-- config reload or service discovery update), the domain-form and resolved-IP
-- form of the same node would be treated as different targets, causing health
-- state to be wiped on every flip between the two. Skip until fully resolved.
local function nodes_resolved(up_conf)
    if not up_conf.nodes then
        return false
    end
    for _, node in ipairs(up_conf.nodes) do
        if not is_ip(node.host) then
            return false
        end
    end
    return true
end


-- Compute the list of healthcheck targets for an upstream config.
-- Returns the ordered target list together with a lookup map keyed by
-- "ip:port:hostname" so that callers can diff two node sets cheaply.
-- The hostname is resolved here (host or node.host) exactly as the
-- healthcheck library would default it, so the same key can be used for
-- both add_target and remove_target.
local function build_targets(up_conf)
    local targets = {}
    local targets_map = {}
    local active = up_conf.checks and up_conf.checks.active
    local host = active and active.host
    local port = active and active.port
    local up_hdr = up_conf.pass_host == "rewrite" and up_conf.upstream_host
    local use_node_hdr = up_conf.pass_host == "node" or nil

    for _, node in ipairs(up_conf.nodes) do
        local host_hdr = up_hdr or (use_node_hdr and node.domain)
        local t_port = port or node.port
        local hostname = host or node.host
        local target = {
            ip = node.host,
            port = t_port,
            hostname = hostname,
            hostheader = host_hdr,
        }
        targets[#targets + 1] = target
        targets_map[node.host .. ":" .. tostring(t_port) .. ":" .. tostring(hostname)] = target
    end

    return targets, targets_map
end


local function create_checker(up_conf)
    if not up_conf.checks then
        return nil
    end
    local local_conf = config_local.local_conf()
    if local_conf and local_conf.apisix and local_conf.apisix.disable_upstream_healthcheck then
        core.log.info("healthchecker won't be created: disabled upstream healthcheck")
        return nil
    end
    core.log.info("creating healthchecker for upstream: ", up_conf.resource_key)
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end

    local checker, err = healthcheck.new({
        name = get_healthchecker_name(up_conf),
        shm_name = healthcheck_shdict_name,
        checks = up_conf.checks,
        events_module = "resty.events",
    })

    if not checker then
        core.log.error("failed to create healthcheck: ", err)
        return nil
    end

    -- Add target nodes
    local targets, targets_map = build_targets(up_conf)
    for _, target in ipairs(targets) do
        local ok, err = checker:add_target(target.ip, target.port, target.hostname,
                                        true, target.hostheader)
        if not ok then
            core.log.error("failed to add healthcheck target: ", target.ip, ":",
                          target.port, " err: ", err)
        end
    end

    return checker, targets_map
end


-- Reconcile a live checker's targets with the current upstream nodes without
-- destroying the checker. Existing targets keep their health status because
-- add_target is a no-op for targets that already exist; only genuinely new
-- nodes are added (as healthy) and removed nodes are deleted from the checker.
local function update_checker_targets(checker, up_conf, old_targets_map)
    local _, new_targets_map = build_targets(up_conf)

    for _, target in pairs(new_targets_map) do
        local ok, err = checker:add_target(target.ip, target.port, target.hostname,
                                        true, target.hostheader)
        if not ok then
            core.log.error("failed to add healthcheck target: ", target.ip, ":",
                          target.port, " err: ", err)
        end
    end

    for key, target in pairs(old_targets_map) do
        if not new_targets_map[key] then
            local ok, err = checker:remove_target(target.ip, target.port, target.hostname)
            if not ok then
                core.log.error("failed to remove healthcheck target: ", target.ip, ":",
                              target.port, " err: ", err)
            else
                core.log.info("removed healthcheck target: ", target.ip, ":", target.port)
            end
        end
    end

    return new_targets_map
end


-- A change is only structural (requires rebuilding the checker) when the
-- checks block itself or the host-header shaping changes. Node additions and
-- removals are handled incrementally so health status is preserved.
local function checks_config_equal(item, up_conf)
    return core.table.deep_eq(item.checks, up_conf.checks)
       and item.pass_host == up_conf.pass_host
       and item.upstream_host == up_conf.upstream_host
end


local function add_working_pool(resource_path, resource_ver, checker, up_conf, targets_map)
    working_pool[resource_path] = {
        version = resource_ver,
        checker = checker,
        checks = up_conf.checks,
        pass_host = up_conf.pass_host,
        upstream_host = up_conf.upstream_host,
        targets_map = targets_map,
    }
end


function _M.fetch_checker(resource_path, resource_ver)
    local working_item = working_pool[resource_path]
    if working_item and working_item.version == resource_ver then
        return working_item.checker
    end

    if waiting_pool[resource_path] == resource_ver then
        return nil
    end

    -- Add to waiting pool with version
    core.log.info("adding ", resource_path, " to waiting pool with version: ", resource_ver)
    waiting_pool[resource_path] = resource_ver
    return nil
end


function _M.fetch_node_status(checker, ip, port, hostname)
    -- check if the checker is valid
    if not checker or checker.dead then
        return true
    end

    return checker:get_target_status(ip, port, hostname)
end


local function get_plugin_name(path)
    -- Extract JSON path (after '#') or use full path
    local json_path = path:match("#(.+)$") or path
    -- Match plugin name in the JSON path segment
    return json_path:match("^plugins%['([^']+)'%]")
        or json_path:match('^plugins%["([^"]+)"%]')
        or json_path:match("^plugins%.([^%.]+)")
end


-- Resolve the upstream config (and its resource_key) from a fetched resource
-- config, transparently handling plugin-provided dynamic upstreams.
-- Returns nil when the resource no longer exists or has no value.
local function resolve_upstream(resource_path, res_conf)
    if not (res_conf and res_conf.value) then
        return nil
    end

    local upstream
    local plugin_name = get_plugin_name(resource_path)
    if plugin_name and plugin_name ~= "" then
        local _, sub_path = config_util.parse_path(resource_path)
        local json_path = "$." .. sub_path
        --- the users of the API pass the jsonpath(in resourcepath) to
        --- upstream_constructor_config which is passed to the
        --- callback construct_upstream to create an upstream dynamically
        local upstream_constructor_config = jp.value(res_conf.value, json_path)
        local plugin = require("apisix.plugins." .. plugin_name)
        upstream = plugin.construct_upstream(upstream_constructor_config)
        upstream.resource_key = resource_path
    else
        upstream = res_conf.value.upstream or res_conf.value
    end

    return upstream
end


-- Bring the checker for a resource in line with the requested upstream config.
-- When the checks configuration is unchanged we only diff the target nodes so
-- that existing health status survives node scaling / discovery updates. A
-- full rebuild only happens when the checks block itself changes.
local function reconcile_checker(resource_path, up_conf, new_version)
    -- Only act on a fully-resolved upstream so target identities stay stable
    -- and match what the balancer queries. An existing checker is left
    -- untouched (its health state preserved) until the nodes resolve again.
    if not nodes_resolved(up_conf) then
        core.log.info("skip reconcile, upstream not fully resolved: ", resource_path)
        return
    end

    local item = working_pool[resource_path]
    if item and item.version == new_version then
        return
    end

    if item and checks_config_equal(item, up_conf) then
        local new_targets_map = update_checker_targets(item.checker, up_conf,
                                                        item.targets_map)
        item.version = new_version
        item.targets_map = new_targets_map
        core.log.info("incrementally updated checker targets: ", tostring(item.checker),
                      " for resource: ", resource_path, " and version: ", new_version)
        return
    end

    if item then
        -- checks configuration changed: rebuild the checker from scratch
        item.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
        item.checker:stop()
        core.log.info("releasing existing checker: ", tostring(item.checker),
                      " for resource: ", resource_path,
                      " due to checks configuration change")
    end

    local checker, targets_map = create_checker(up_conf)
    if not checker then
        return
    end
    core.log.info("create new checker: ", tostring(checker), " for resource: ",
                resource_path, " and version: ", new_version)
    add_working_pool(resource_path, new_version, checker, up_conf, targets_map)
end


local function timer_create_checker()
    if core.table.nkeys(waiting_pool) == 0 then
        return
    end

    local waiting_snapshot = tab_clone(waiting_pool)
    for resource_path in pairs(waiting_snapshot) do
        do
            local res_conf = resource.fetch_latest_conf(resource_path)
            local upstream = resolve_upstream(resource_path, res_conf)
            if not upstream then
                goto continue
            end
            -- always reconcile against the latest known version instead of the
            -- version that was requested when the resource was queued; this
            -- avoids a race where the queued version is already stale and the
            -- checker would otherwise never be (re)created.
            local new_version = upstream_utils.version(res_conf.modifiedIndex,
                                                             upstream._nodes_ver)
            core.log.info("checking waiting pool for resource: ", resource_path,
                    " current version: ", new_version)
            reconcile_checker(resource_path, upstream, new_version)
        end

        ::continue::
        waiting_pool[resource_path] = nil
    end
end


local function timer_working_pool_check()
    if core.table.nkeys(working_pool) == 0 then
        return
    end

    local working_snapshot = tab_clone(working_pool)
    for resource_path, item in pairs(working_snapshot) do
        local res_conf = resource.fetch_latest_conf(resource_path)
        local upstream = resolve_upstream(resource_path, res_conf)

        if not upstream then
            --- resource doesn't exist anymore, destroy the checker
            working_pool[resource_path] = nil
            item.checker.dead = true
            item.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
            item.checker:stop()
            core.log.info("try to release checker: ", tostring(item.checker), " for resource: ",
                        resource_path, " and version : ", item.version)
        else
            local current_ver = upstream_utils.version(res_conf.modifiedIndex,
                                                    upstream._nodes_ver)
            core.log.info("checking working pool for resource: ", resource_path,
                        " current version: ", current_ver, " item version: ", item.version)
            if item.version ~= current_ver then
                --- nodes and/or checks changed, reconcile without losing
                --- health state where possible
                reconcile_checker(resource_path, upstream, current_ver)
            end
        end
    end
end

function _M.init_worker()
    local timer_create_checker_running = false
    local timer_working_pool_check_running = false
    timer_every(1, function ()
        if not exiting() then
            if timer_create_checker_running then
                core.log.warn("timer_create_checker is already running, skipping this iteration")
                return
            end
            timer_create_checker_running = true
            local ok, err = pcall(timer_create_checker)
            if not ok then
                core.log.error("failed to run timer_create_checker: ", err)
            end
            timer_create_checker_running = false
        end
    end)
    timer_every(1, function ()
        if not exiting() then
            if timer_working_pool_check_running then
                core.log.warn("timer_working_pool_check is already running skipping iteration")
                return
            end
            timer_working_pool_check_running = true
            local ok, err = pcall(timer_working_pool_check)
            if not ok then
                core.log.error("failed to run timer_working_pool_check: ", err)
            end
            timer_working_pool_check_running = false
        end
    end)
end

return _M
