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
-- Slow start (`upstream.slow_start`): a node that the data plane observes for
-- the first time takes a reduced share of the traffic and ramps back to its
-- configured weight over `slow_start_time_seconds`.
--
-- Which node is new is decided here, by comparing the node set of the current
-- picker build against the set the previous build recorded. No node lifecycle
-- timestamp is read from the configuration, the Admin API or service discovery:
-- every start point is generated locally with `ngx.now()` and lives only in the
-- `upstream-slow-start` shared dict, so it is never written back to etcd.
--
-- Shared dict layout, all keys prefixed by the upstream scope (the resource key
-- of the standalone upstream, or of the route/service that embeds it):
--
--   <scope>|#               node ids the configuration held at the previous reconcile
--   <scope>|!               aggregate ramp deadline, read on the request hot path
--   <scope>|<id>            ramp start: > 0 ramping, 0 mature, -1 not picked yet
--   <scope>|<id>|i          when a reconcile first saw it configured but unpickable
--   <scope>|<id>@<start>    the successor a worker elected for that ramp start
--
-- Workers reconcile in parallel, and the shared dict has no compare-and-set, so
-- a value is never derived from a read and then written back blindly: a worker
-- that read a ramp start just before another one changed it would put the old
-- one back. Instead a node's ramp start is only ever created with `add`, only
-- ever replaced through an election on `add` keyed by the value being replaced,
-- and otherwise kept alive with `expire`, which leaves the value alone. Every
-- worker that decides on a change to the same ramp start therefore ends up
-- writing the same successor.
--
-- Presence and eligibility are tracked separately. Presence comes from the
-- configuration, so every worker sees the same set; eligibility is this worker's
-- health view and only decides when a ramp starts and when it is interrupted.
-- Tombstoning off the eligible set would let one worker's transient health
-- opinion drop a node the other workers are still serving, and the state of a
-- node that never left could then expire and be ramped again from scratch.
--
-- A node the configuration still holds keeps its entry alive. One that leaves the
-- configuration keeps it for a further `slow_start_time_seconds` (the tombstone
-- window) so a short absence resumes the ramp instead of restarting it. Coming
-- back later, or being out of the picker for longer than a full window, starts a
-- new lifecycle.
local core         = require("apisix.core")
local ipairs       = ipairs
local pairs        = pairs
local tostring     = tostring
local tonumber     = tonumber
local os_time      = os.time
local ngx_now      = ngx.now
local math_floor   = math.floor
local math_max     = math.max
local math_min     = math.min
local str_gmatch   = string.gmatch
local type         = type

local shdict = ngx.shared["upstream-slow-start"]

local INSTANCE_STARTED_KEY = "@instance_started_at"
local SNAPSHOT_SUFFIX      = "|#"
local DEADLINE_SUFFIX      = "|!"
local INELIGIBLE_SUFFIX    = "|i"

-- A node that is present but needs no ramp is stored with this ramp start, so
-- that it can still be tombstoned when it disappears: without an entry it would
-- look new again on its way back.
local MATURE = 0

-- And one the configuration holds but that has never reached a picker - an
-- active health check has not cleared it yet - is stored with this one. It is
-- what separates "known and already mature" from "known but has not had its
-- chance to ramp", which otherwise both look like a node with no state.
local PENDING = -1

-- Lifetime of the state of a node that is still eligible. Refreshed on every
-- reconcile, which a busy upstream runs at least as often as the picker LRU
-- expires (300s), so it only ever elapses for an upstream that stopped receiving
-- traffic altogether. State lost that way makes the whole node set a fresh mature
-- baseline again, which is the safe direction, and it is also what keeps the
-- state of a deleted upstream from living forever.
local STATE_TTL = 86400

-- Lifetime of an election on a ramp start, see `replace_start`.
local ELECTION_TTL = 10

local _M = {}


local reported_scopes = {}


local function report_once(scope, ...)
    if reported_scopes[scope] then
        return
    end
    reported_scopes[scope] = true
    core.log.error(...)
end


-- The instance start point behind `startup_grace_period_seconds`. Written from
-- the master process with `add`, so a HUP reload - which keeps the shared dict -
-- continues to use the start point of the original start.
function _M.init()
    if not shdict then
        return
    end

    local ok, err = shdict:add(INSTANCE_STARTED_KEY, os_time())
    if not ok and err ~= "exists" then
        core.log.error("failed to record the slow start instance start time: ", err)
    end
end


local function scope_key(up_conf)
    return up_conf.resource_key
end


-- The lifecycle identity of a node. Service discovery that knows which workload
-- answers on an address says so in `metadata.uid` - Kubernetes puts the Pod
-- there - and that is the better identity: an address a different Pod takes over
-- is a different node and ramps again, while a Pod that changes address keeps
-- the progress it had. A domain node is identified by the hostname it was
-- configured with, not by the address it currently resolves to, so a DNS
-- rotation does not restart its ramp either.
local function node_id(node)
    local uid = node.metadata and node.metadata.uid
    if uid then
        return uid .. ":" .. tostring(node.port)
    end

    return (node.domain or node.host) .. ":" .. tostring(node.port)
end


local function effective_weight(original_weight, first_seen_at, conf, now)
    if original_weight <= 0 then
        -- a node configured out of the rotation stays out of it
        return original_weight
    end

    if not first_seen_at or first_seen_at <= MATURE then
        return original_weight
    end

    local window = conf.slow_start_time_seconds
    local elapsed = now - first_seen_at
    if elapsed < 0 then
        -- the local clock moved backwards; start the window over rather than
        -- letting a negative elapsed produce a complex power below
        elapsed = 0
    end
    if elapsed >= window then
        return original_weight
    end

    -- `max(elapsed, 1)` keeps the first bucket at one second of progress, so a
    -- node never ramps from exactly zero
    local time_factor = math_max(elapsed, 1) / window
    local ratio = math_max(conf.min_weight_percent / 100,
                           time_factor ^ (1 / (conf.aggression or 1)))
    local weight = math_floor(original_weight * ratio)
    if weight < 1 then
        -- integer weights: anything above zero has to keep at least one unit,
        -- otherwise the node gets no traffic at all and never warms up
        weight = 1
    end

    return weight
end
_M.effective_weight = effective_weight


-- The weight a node ramps up to. A Kubernetes endpoint has no weight of its own,
-- so the registry gives every one of them the same `default_weight`; an upstream
-- that wants a different target for its own ramp says so in `slow_start`. Any
-- other source carries weights that mean something, and they are left alone.
local function target_weight(up_conf, conf, node)
    if conf.default_weight and up_conf.discovery_type == "kubernetes" then
        return conf.default_weight
    end

    return node.weight
end


local function within_startup_grace(conf, now)
    local grace = conf.startup_grace_period_seconds or 0
    if grace <= 0 then
        return false
    end

    local started_at = shdict:get(INSTANCE_STARTED_KEY)
    if not started_at then
        return false
    end

    return now < started_at + grace
end


local function decode_snapshot(snapshot)
    local known = {}
    if not snapshot then
        return nil
    end

    for id in str_gmatch(snapshot, "[^,]+") do
        known[id] = true
    end
    return known
end


local function store(key, value, ttl)
    local ok, err, forcible = shdict:set(key, value, ttl)
    if not ok then
        core.log.error("failed to store the slow start state of ", key, ": ", err)
    elseif forcible then
        core.log.warn("the upstream-slow-start shared dict is full, storing ", key,
                      " evicted another entry; nodes whose state is lost keep ",
                      "their configured weight")
    end
    return ok
end


local function keep_alive(key, ttl)
    local ok, err = shdict:expire(key, ttl)
    if not ok and err ~= "not found" then
        core.log.error("failed to refresh the slow start state of ", key, ": ", err)
    end
end


-- Create the ramp start of a node that has none, or adopt the one another worker
-- created first. Returns the ramp start everyone now shares, and whether this
-- worker is the one that set it.
local function create_start(key, candidate)
    local ok, err, forcible = shdict:add(key, candidate, STATE_TTL)
    if ok then
        if forcible then
            core.log.warn("the upstream-slow-start shared dict is full, storing ", key,
                          " evicted another entry")
        end
        return candidate, true
    end

    if err ~= "exists" then
        core.log.error("failed to store the slow start state of ", key, ": ", err)
        return MATURE, false
    end

    return tonumber(shdict:get(key)) or candidate, false
end


-- Replace the ramp start `from` with `to`, unless another worker already elected
-- a successor for `from`, in which case that one is used. The election outlives
-- the few microseconds a worker spends between reading `from` and getting here
-- by a wide margin, and is short enough that `from` cannot come round again for
-- the same node before it expires.
local function replace_start(key, from, to, window)
    local election = key .. "@" .. from
    local won, err = shdict:add(election, to, math_min(window, ELECTION_TTL))
    if not won then
        if err == "exists" then
            to = tonumber(shdict:get(election)) or to
        else
            core.log.error("failed to elect the slow start state of ", key, ": ", err)
        end
    end

    store(key, to, STATE_TTL)
    return to, won
end


-- Compare the node set of this picker build against the one the previous build
-- recorded, and return the ramp start point of every eligible node, indexed like
-- `nodes`. `present_nodes` is the configured set, identical in every worker;
-- `nodes` is the subset this worker can actually pick from.
local function reconcile(conf, present_nodes, nodes, scope, now)
    local window = conf.slow_start_time_seconds

    local present_ids = core.table.new(#present_nodes, 0)
    local present = core.table.new(0, #present_nodes)
    for i, node in ipairs(present_nodes) do
        present_ids[i] = node_id(node)
        present[present_ids[i]] = true
    end

    local ids = core.table.new(#nodes, 0)
    local eligible = core.table.new(0, #nodes)
    for i, node in ipairs(nodes) do
        ids[i] = node_id(node)
        eligible[ids[i]] = true
    end

    local snapshot_key = scope .. SNAPSHOT_SUFFIX
    local known = decode_snapshot(shdict:get(snapshot_key))

    -- The first reconcile of a scope is a baseline: the nodes an upstream is
    -- bootstrapped with, and the nodes it already had when `slow_start` was
    -- turned on, are mature. So are nodes observed inside the startup grace
    -- period, which absorbs the ordering differences of a cold restart.
    local baseline = (known == nil) or within_startup_grace(conf, now)

    local first_seen = core.table.new(#nodes, 0)
    local deadline = 0

    local function log_began(id, weight)
        core.log.info("slow start began for node ", id, " of upstream ", scope,
                      ", weight ", weight, ", window ", window, "s, from ", now)
    end

    for i, id in ipairs(ids) do
        local key = scope .. "|" .. id
        local ineligible_key = key .. INELIGIBLE_SUFFIX
        local start_at = tonumber(shdict:get(key))
        local ineligible_since = tonumber(shdict:get(ineligible_key))
        local changed

        if not start_at then
            if baseline or (known and known[id]) then
                -- either the bootstrap set, or a node whose state the shared dict
                -- evicted while it stayed configured: both keep the full weight
                -- rather than ramping a node that has been serving all along
                start_at = create_start(key, MATURE)
            else
                start_at, changed = create_start(key, now)
                if changed then
                    log_began(id, nodes[i].weight)
                end
            end

        elseif start_at == PENDING then
            -- the first picker it can actually be part of: this is where its
            -- window starts, not when the configuration first mentioned it
            start_at, changed = replace_start(key, PENDING, now, window)
            if changed then
                log_began(id, nodes[i].weight)
            end

        elseif ineligible_since and now - ineligible_since > window then
            -- observed out of the picker for longer than a full window: whatever
            -- answers on this address now is not the process that was ramping
            local out_for = now - ineligible_since
            start_at, changed = replace_start(key, start_at, now, window)
            if changed then
                core.log.info("slow start restarted for node ", id, " of upstream ",
                              scope, " after ", out_for, "s out of the picker")
            end

        elseif start_at > MATURE and now - start_at >= window then
            start_at, changed = replace_start(key, start_at, MATURE, window)
            if changed then
                core.log.info("slow start finished for node ", id, " of upstream ",
                              scope)
            end

        else
            -- refresh the lifetime, which also drops the tombstone window if the
            -- node came back after having left the configuration
            keep_alive(key, STATE_TTL)
        end

        if ineligible_since then
            -- back in the picker
            shdict:delete(ineligible_key)
        end

        first_seen[i] = start_at
        if start_at > MATURE then
            deadline = math_max(deadline, start_at + window)
        end
    end

    for _, id in ipairs(present_ids) do
        if not eligible[id] then
            local key = scope .. "|" .. id
            local start_at = tonumber(shdict:get(key))
            if start_at then
                -- still configured, just not pickable here: keep the state alive
                -- and mark when it dropped out, keeping the earliest mark. The
                -- ramp clock itself runs on, so a short outage resumes where it
                -- left off
                keep_alive(key, STATE_TTL)
                local ineligible_key = key .. INELIGIBLE_SUFFIX
                if not shdict:add(ineligible_key, now, STATE_TTL) then
                    keep_alive(ineligible_key, STATE_TTL)
                end
            elseif baseline or (known and known[id]) then
                -- part of the bootstrap set even though a health check has not
                -- cleared it yet, or state the shared dict evicted: every node
                -- the previous reconcile saw was given state then
                start_at = create_start(key, MATURE)
            else
                -- configured but never picked: its window starts when it first
                -- becomes usable
                start_at = create_start(key, PENDING)
            end

            -- a ramp this worker cannot pick from is still a ramp other workers
            -- may be serving, and the deadline is what keeps their picker keys
            -- moving; leaving it out would let this worker publish an early one
            if start_at > MATURE then
                deadline = math_max(deadline, start_at + window)
            end
        end
    end

    -- A node that left the configuration keeps its state for one slow start
    -- window and is then forgotten, so that the address coming back later - a
    -- different process behind the same host and port - is warmed up again.
    if known then
        for id in pairs(known) do
            if not present[id] then
                local key = scope .. "|" .. id
                if shdict:get(key) then
                    core.log.info("node ", id, " of upstream ", scope,
                                  " left the upstream, keeping its slow start state for ",
                                  window, "s")
                    keep_alive(key, window)
                    keep_alive(key .. INELIGIBLE_SUFFIX, window)
                end
            end
        end
    end

    core.table.sort(present_ids)
    store(snapshot_key, core.table.concat(present_ids, ","), STATE_TTL)
    -- published for the hot path: zero means every node is mature
    store(scope .. DEADLINE_SUFFIX, deadline, STATE_TTL)

    return first_seen
end


local function usable(up_conf, nodes)
    local scope = scope_key(up_conf)
    if not scope then
        core.log.error("slow start needs an upstream with a resource key, ",
                       "ignoring slow_start")
        return nil
    end

    if not shdict then
        -- slow start only ramps HTTP upstreams, and the stream subsystem has no
        -- such shared dict. Like every other upstream field that does not apply
        -- there, `slow_start` is quietly ignored and the configured weights are
        -- used, rather than failing the connection or logging on every build
        return nil
    end

    if up_conf.type ~= "roundrobin" then
        report_once(scope, "slow start only supports roundrobin, ignoring ",
                    "slow_start of upstream ", scope)
        return nil
    end

    if nodes then
        local priority = nodes[1] and nodes[1].priority
        for _, node in ipairs(nodes) do
            if node.priority ~= priority then
                report_once(scope, "slow start does not support an upstream with ",
                            "mixed node priorities, ignoring slow_start of upstream ",
                            scope)
                return nil
            end
        end
    end

    return scope
end


-- Effective weight of every node of this picker build, indexed like `nodes`, or
-- nil when the upstream does not use slow start. Runs once per picker build, not
-- per request.
function _M.effective_weights(up_conf, nodes)
    local conf = up_conf.slow_start
    if type(conf) ~= "table" then
        return nil
    end

    local scope = usable(up_conf, nodes)
    if not scope then
        -- settle the picker cache key: without a deadline `version_suffix` keeps
        -- appending a fresh time bucket, so an upstream that can never ramp would
        -- rebuild its picker every `interval` for nothing
        if shdict and up_conf.resource_key then
            store(up_conf.resource_key .. DEADLINE_SUFFIX, 0, STATE_TTL)
        end
        return nil
    end

    local now = ngx_now()
    local first_seen = reconcile(conf, up_conf.nodes, nodes, scope, now)

    local weights = core.table.new(#nodes, 0)
    for i, node in ipairs(nodes) do
        weights[i] = effective_weight(target_weight(up_conf, conf, node),
                                      first_seen[i], conf, now)
    end

    return weights
end


-- Suffix of the picker cache key. While any node ramps, the key carries the
-- current `interval` bucket so that the picker is rebuilt once per bucket per
-- worker; once every node is mature the key settles on a stable suffix, and the
-- rebuild it causes is the one that restores the full weights.
--
-- A rebuild restarts the round robin cursor, which favours the heaviest node for
-- the first few picks. Over a bucket that carries real traffic this averages out,
-- but on an upstream that sees only a handful of requests per `interval` the
-- ramping node can end up with even less traffic than its weight asks for.
function _M.version_suffix(up_conf)
    local conf = up_conf.slow_start
    if type(conf) ~= "table" or not shdict or not up_conf.resource_key
       or up_conf.type ~= "roundrobin" then
        return nil
    end

    local now = ngx_now()
    local deadline = shdict:get(up_conf.resource_key .. DEADLINE_SUFFIX)
    -- an unknown deadline means no picker has been built for this upstream yet;
    -- the build that this bucket triggers is the one that publishes it
    if deadline and now >= deadline then
        return "#wm"
    end

    return "#w" .. math_floor(now / (conf.interval or 1))
end


return _M
