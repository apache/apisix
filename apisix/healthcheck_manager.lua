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
-- resource_path -> {version = ver, checker = checker, checks = checks}
local working_pool = {}
local waiting_pool = {}      -- resource_path -> resource_ver

local DELAYED_CLEAR_TIMEOUT = 10
local healthcheck_shdict_name = "upstream-healthcheck"


local function get_healthchecker_name(value)
    return "upstream#" .. (value.resource_key or value.upstream.resource_key)
end
_M.get_healthchecker_name = get_healthchecker_name


-- Compute the desired set of health-check targets for an upstream config.
-- Returns an ordered array preserving up_conf.nodes order so that targets are
-- always added to a checker deterministically; each entry also carries a
-- "host:port:hostname:hostheader" key so the working set can be diffed cheaply
-- against a checker's current targets. The key mirrors resty.healthcheck's target
-- identity (ip+port+hostname) plus the Host header, so a checks.active.host change
-- (which changes the hostname) is treated as a different target and its stale shm
-- entry is removed instead of colliding on the same key.
local function compute_targets(up_conf)
    local host = up_conf.checks and up_conf.checks.active and up_conf.checks.active.host
    local port = up_conf.checks and up_conf.checks.active and up_conf.checks.active.port
    local up_hdr = up_conf.pass_host == "rewrite" and up_conf.upstream_host

    local targets = {}
    for _, node in ipairs(up_conf.nodes) do
        -- A health check has no client; the gateway probes the node by the node's own
        -- identity (its domain), so use node.domain as the Host header regardless of
        -- pass_host (except "rewrite", which pins an explicit Host). Otherwise a domain
        -- node probes with the resolved ip as Host/SNI, breaking HTTPS health checks.
        -- node.domain is nil for ip nodes.
        local host_hdr = up_hdr or node.domain
        local target_port = port or node.port
        -- add_target defaults the hostname to the ip when checks.active.host is
        -- unset, so mirror that here to match the shm entry's stored hostname
        local hostname = host or node.host
        targets[#targets + 1] = {
            host = node.host,
            port = target_port,
            check_host = host,
            host_hdr = host_hdr,
            key = node.host .. ":" .. tostring(target_port) .. ":" .. tostring(hostname)
                  .. ":" .. tostring(host_hdr or ""),
        }
    end
    return targets
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

    local targets = compute_targets(up_conf)
    local desired = {}
    for _, target in ipairs(targets) do
        desired[target.key] = true
    end

    -- Remove stale targets from the shared shm BEFORE adding, mirroring
    -- sync_checker_targets. resty.healthcheck keys a target by ip+port+hostname
    -- (the Host header is not part of that identity), so a Host-header-only change
    -- must free the old identity first -- otherwise add_target is a no-op on the
    -- existing identity and the following remove_target then wipes the
    -- still-desired target. The shm may also hold nodes another worker created and
    -- this config later dropped (apache/apisix#13282, multi-worker).
    local target_list = healthcheck.get_target_list(get_healthchecker_name(up_conf),
                                                    healthcheck_shdict_name) or {}
    for _, t in ipairs(target_list) do
        local key = t.ip .. ":" .. tostring(t.port) .. ":" .. tostring(t.hostname)
                    .. ":" .. tostring(t.hostheader or "")
        if not desired[key] then
            local ok, err = checker:remove_target(t.ip, t.port, t.hostname)
            if not ok then
                core.log.error("failed to remove healthcheck target: ", t.ip, ":",
                              t.port, " err: ", err)
            end
        end
    end

    -- Add all desired nodes, in node order. Re-adding an already-present target is
    -- a no-op except that it clears any pending purge_time, which is what un-marks
    -- surviving targets after a delayed_clear() on a checks-config rebuild.
    for _, target in ipairs(targets) do
        local ok, err = checker:add_target(target.host, target.port, target.check_host,
                                        true, target.host_hdr)
        if not ok then
            core.log.error("failed to add healthcheck target: ", target.host, ":",
                          target.port, " err: ", err)
        end
    end

    return checker
end


-- Incrementally reconcile an existing checker's targets to match up_conf.
-- Used when only the upstream nodes changed but the `checks` config did not,
-- so the checker can keep running (and keep its accumulated health state)
-- instead of being destroyed and rebuilt.
-- Returns true only if every add/remove succeeded; on a partial failure the
-- caller must not treat the checker as reconciled for this version.
local function sync_checker_targets(checker, up_conf)
    -- index the desired targets by key so they can be diffed against current;
    -- keep the ordered list too so adds preserve node order (deterministic)
    local targets = compute_targets(up_conf)
    local desired = {}
    for _, target in ipairs(targets) do
        desired[target.key] = target
    end

    -- index current targets the same way as desired. Read the authoritative
    -- shm target list (the per-worker checker.targets array can lag behind a
    -- recent add/remove event).
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end
    local current = {}
    local target_list = healthcheck.get_target_list(get_healthchecker_name(up_conf),
                                                    healthcheck_shdict_name) or {}
    for _, t in ipairs(target_list) do
        -- target_list entries carry hostheader; map it back to our key shape
        local key = t.ip .. ":" .. tostring(t.port) .. ":" .. tostring(t.hostname)
                    .. ":" .. tostring(t.hostheader or "")
        current[key] = t
    end

    local synced = true

    -- Remove stale targets BEFORE adding new ones. resty.healthcheck identifies a
    -- target by ip+port+hostname; the Host header is not part of that identity. A
    -- Host-header-only change (e.g. pass_host/upstream_host) therefore produces a
    -- removal of the old key and an addition of the new key for the same identity.
    -- Removing first frees that identity so the following add_target actually
    -- applies the new Host header instead of being a no-op on an existing target.
    for key, t in pairs(current) do
        if not desired[key] then
            local ok, err = checker:remove_target(t.ip, t.port, t.hostname)
            if not ok then
                synced = false
                core.log.error("failed to remove healthcheck target: ", t.ip, ":",
                              t.port, " err: ", err)
            end
        end
    end

    -- add targets that are desired but not present, in node order. Unlike
    -- create_checker this does not re-add already-present targets, so it cannot
    -- un-mark a pending purge_time. That is safe here only because sync runs on a
    -- reuse-eligible checker (checks unchanged), which is never delayed_clear'd --
    -- delayed_clear only happens on a checks-change rebuild or a destroy.
    for _, target in ipairs(targets) do
        if not current[target.key] then
            local ok, err = checker:add_target(target.host, target.port, target.check_host,
                                            true, target.host_hdr)
            if not ok then
                synced = false
                core.log.error("failed to add healthcheck target: ", target.host, ":",
                              target.port, " err: ", err)
            end
        end
    end

    return synced
end


function _M.fetch_checker(resource_path, resource_ver)
    local working_item = working_pool[resource_path]
    if working_item and working_item.version == resource_ver then
        return working_item.checker
    end

    -- The requested version differs from the working checker -- e.g. a
    -- discovery/DNS change bumped _nodes_ver. Enqueue the new version so
    -- timer_create_checker reconciles (or rebuilds) it, but keep returning the
    -- existing live checker in the meantime: its accumulated health state is
    -- still valid, so requests during the ~1s transition keep filtering
    -- unhealthy nodes instead of falling back to "all nodes available", which
    -- would let a node already known to be unhealthy receive traffic
    -- (apache/apisix#13282).
    if waiting_pool[resource_path] ~= resource_ver then
        core.log.info("adding ", resource_path, " to waiting pool with version: ", resource_ver)
        waiting_pool[resource_path] = resource_ver
    end

    if working_item and working_item.checker and not working_item.checker.dead then
        return working_item.checker
    end

    return nil
end


function _M.fetch_node_status(checker, ip, port, hostname)
    -- check if the checker is valid
    if not checker or checker.dead then
        return true
    end

    local ok, err = checker:get_target_status(ip, port, hostname)
    if err == "target not found" then
        -- get_target_status reads a worker-local cache that resty.healthcheck fills
        -- asynchronously (add_target only raises an event), so right after a checker
        -- is created a target can be missing from this worker's view even though it
        -- is registered in the shm and being probed. Treat it as unknown (usable)
        -- rather than unhealthy, but still log it: a target that stays missing means
        -- the cache never converged, a real bug worth surfacing rather than swallowing.
        core.log.warn("health check target status not available yet, treat as unknown",
                      ", addr: ", ip, ":", port, ", host: ", hostname)
        return true
    end

    return ok, err
end


local function add_working_pool(resource_path, resource_ver, checker, checks)
    working_pool[resource_path] = {
        version = resource_ver,
        checker = checker,
        checks = checks,
    }
end

local function find_in_working_pool(resource_path, resource_ver)
    local checker = working_pool[resource_path]
    if not checker then
        return nil  -- not found
    end

    if checker.version ~= resource_ver then
        core.log.info("version mismatch for resource: ", resource_path,
                    " current version: ", checker.version, " requested version: ", resource_ver)
        return nil  -- version not match
    end
    return checker
end


local function get_plugin_name(path)
    -- Extract JSON path (after '#') or use full path
    local json_path = path:match("#(.+)$") or path
    -- Match plugin name in the JSON path segment
    return json_path:match("^plugins%['([^']+)'%]")
        or json_path:match('^plugins%["([^"]+)"%]')
        or json_path:match("^plugins%.([^%.]+)")
end

local function timer_create_checker()
    if core.table.nkeys(waiting_pool) == 0 then
        return
    end

    local waiting_snapshot = tab_clone(waiting_pool)
    for resource_path, resource_ver in pairs(waiting_snapshot) do
        do
            if find_in_working_pool(resource_path, resource_ver) then
                core.log.info("resource: ", resource_path,
                             " already in working pool with version: ",
                               resource_ver)
                goto continue
            end
            local res_conf = resource.fetch_latest_conf(resource_path)
            if not res_conf then
                goto continue
            end
            local ok, upstream, err
            local plugin_name = get_plugin_name(resource_path)
            if plugin_name and plugin_name ~= "" then
                local _, sub_path = config_util.parse_path(resource_path)
                local json_path = "$." .. sub_path
                --- the users of the API pass the jsonpath(in resourcepath) to
                --- upstream_constructor_config which is passed to the
                --- callback construct_upstream to create an upstream dynamically
                local upstream_constructor_config = jp.value(res_conf.value, json_path)
                local plugin = require("apisix.plugins." .. plugin_name)
                ok, upstream, err = pcall(plugin.construct_upstream, upstream_constructor_config)
                if not ok or not upstream then
                    err = err or upstream
                    core.log.error("[creating checker] unable to construct upstream",
                                " for plugin: ", plugin_name, ", resource path: ", resource_path,
                                ", json path: ", json_path, ", error: ", err)
                    goto continue
                end
                upstream.resource_key = resource_path
            else
                upstream = res_conf.value.upstream or res_conf.value
            end
            local new_version = upstream_utils.version(res_conf.modifiedIndex,
                                                             upstream._nodes_ver)
            core.log.info("checking waiting pool for resource: ", resource_path,
                    " current version: ", new_version, " requested version: ", resource_ver)
            if resource_ver ~= new_version then
                goto continue
            end

            -- No nodes means there is nothing to health-check. Don't build (or
            -- rebuild into) an empty checker here; leave any teardown to
            -- timer_working_pool_check, which destroys the checker when the node
            -- count drops to 0, so the two timers stay consistent.
            if not upstream.nodes or #upstream.nodes == 0 then
                goto continue
            end

            -- Reuse path: if a checker exists and the `checks` config is unchanged
            -- (only the nodes changed), reconcile its targets in place instead of
            -- rebuilding. Rebuilding leaves fetch_checker with no checker for the
            -- rebuild window (traffic then skips health filtering) and discards the
            -- accumulated health state. sync_checker_targets is the last condition so
            -- it runs only when the checker is reuse-eligible; a partial failure makes
            -- the guard false and falls through to the full rebuild below.
            -- upstream.nodes is non-empty here (guaranteed by the 0-node guard above).
            local existing_checker = working_pool[resource_path]
            if existing_checker and existing_checker.checker
               and not existing_checker.checker.dead
               and upstream.checks
               and core.table.deep_eq(existing_checker.checks, upstream.checks)
               and sync_checker_targets(existing_checker.checker, upstream) then
                add_working_pool(resource_path, resource_ver, existing_checker.checker,
                                 upstream.checks)
                core.log.info("reused checker with incremental targets: ",
                              tostring(existing_checker.checker), " for resource: ",
                              resource_path, " and version: ", resource_ver)
                goto continue
            end

            -- Rebuild path: checks changed (or no checker exists). delayed_clear()
            -- MUST run before create_checker() re-adds the targets -- the new checker
            -- shares the same shm target list, and add_target() only un-marks a
            -- target's purge_time when re-added *after* it was marked. Clearing first
            -- lets surviving targets get un-marked on re-add while genuinely dropped
            -- targets keep their purge_time; clearing after would leave live targets
            -- marked and purge them later. The old checker is stopped only after the
            -- new one is published, so this path never exposes a nil checker.
            if existing_checker then
                existing_checker.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
            end
            local checker = create_checker(upstream)
            if not checker then
                -- create_checker failed (upstream healthcheck disabled or
                -- healthcheck.new errored). The old checker's shm targets were
                -- already delayed_clear'd above, so it can no longer health-check
                -- reliably; tear it down and drop it from the working pool instead
                -- of leaving a stopped/cleared checker that fetch_checker would
                -- still hand out (it only checks .dead).
                if existing_checker then
                    core.log.warn("releasing existing checker after create failed: ",
                                  tostring(existing_checker.checker), " for resource: ",
                                  resource_path, " and version: ", existing_checker.version)
                    existing_checker.checker.dead = true
                    existing_checker.checker:stop()
                    working_pool[resource_path] = nil
                end
                goto continue
            end
            core.log.info("create new checker: ", tostring(checker), " for resource: ",
                        resource_path, " and version: ", resource_ver)
            add_working_pool(resource_path, resource_ver, checker, upstream.checks)
            if existing_checker then
                existing_checker.checker.dead = true
                existing_checker.checker:stop()
                core.log.info("releasing existing checker: ", tostring(existing_checker.checker),
                              " for resource: ", resource_path, " and version: ",
                              existing_checker.version)
            end
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
        --- remove from working pool if resource doesn't exist
        local res_conf = resource.fetch_latest_conf(resource_path)
        local need_destroy = true
        if res_conf and res_conf.value then
            local ok, upstream, err
            local plugin_name = get_plugin_name(resource_path)
            if plugin_name and plugin_name ~= "" then
                local _, sub_path = config_util.parse_path(resource_path)
                local json_path = "$." .. sub_path
                --- the users of the API pass the jsonpath(in resourcepath) to
                --- upstream_constructor_config which is passed to the
                --- callback construct_upstream to create an upstream dynamically
                local upstream_constructor_config = jp.value(res_conf.value, json_path)
                local plugin = require("apisix.plugins." .. plugin_name)
                ok, upstream, err = pcall(plugin.construct_upstream, upstream_constructor_config)
                if not ok or not upstream then
                    -- a nil constructor config means the instance was removed, so let
                    -- the checker be destroyed; otherwise keep it through a transient failure
                    if upstream_constructor_config ~= nil then
                        need_destroy = false
                    end
                    err = err or upstream or "unknown error"
                    upstream = nil
                    local err_msg = "[checking checker] unable to construct upstream for plugin: "
                                .. plugin_name .. ", resource path: " .. resource_path
                                .. ", json path: " .. json_path .. ", error: " .. err
                    if not ok then
                        core.log.error(err_msg)
                    else
                        core.log.warn(err_msg)
                    end
                else
                    upstream.resource_key = resource_path
                end
            else
                upstream = res_conf.value.upstream or res_conf.value
            end
            if upstream then
                local current_ver = upstream_utils.version(res_conf.modifiedIndex,
                                                        upstream._nodes_ver)
                core.log.info("checking working pool for resource: ", resource_path,
                            " current version: ", current_ver, " item version: ", item.version)
                if item.version == current_ver then
                    need_destroy = false
                elseif upstream.checks and upstream.nodes and #upstream.nodes > 0 then
                    -- The version changed but the upstream still defines checks and
                    -- keeps at least one node, so a same-name checker must stay alive.
                    -- Do NOT destroy here (whether the change is nodes-only or a checks
                    -- change): keep this checker and let timer_create_checker transition
                    -- it -- a nodes-only change is reconciled incrementally, a checks
                    -- change is rebuilt there by building the new checker first and only
                    -- then stopping the old one. Destroying here would blank
                    -- working_pool until the next timer_create_checker tick, reopening
                    -- the nil window (fetch_checker returns nil -> health filtering
                    -- bypassed) this PR closes; on multi-worker it would also clear the
                    -- shared shm and purge a peer worker's live targets
                    -- (apache/apisix#13282). Enqueue the rebuild so it runs on this
                    -- timer even without traffic. When the node count drops to 0 we fall
                    -- through to destroy, matching the original behaviour.
                    need_destroy = false
                    if waiting_pool[resource_path] ~= current_ver then
                        waiting_pool[resource_path] = current_ver
                    end
                end
            end
        end

        if need_destroy then
            -- Reached only when no same-name checker will own the shared shm target
            -- list: the resource was deleted, or the new config has no checks/nodes.
            -- (A version change that still has checks and nodes is handled above by
            -- keeping the checker alive, so it never clears a peer's live targets.)
            working_pool[resource_path] = nil
            item.checker.dead = true
            item.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
            item.checker:stop()
            core.log.info("try to release checker: ", tostring(item.checker), " for resource: ",
                        resource_path, " and version : ", item.version)
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
