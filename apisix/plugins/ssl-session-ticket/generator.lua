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

--- Built-in generator and local policy executor of ssl-session-ticket.
--
-- It runs in the privileged agent of the traditional and control_plane nodes
-- backed by etcd. Each round compares the record with the local policy and,
-- when they differ or a rotation is due, rewrites the record with an etcd
-- transaction against the revision it has read: when several nodes act on
-- the same revision, only one of them succeeds. Rounds pause as long as the
-- live nodes do not share the same policy.
--
-- Rotation is timed by `origin.generated_at` of the record, not by the
-- process: a restart does not restart the period, and a node that comes back
-- after a long pause rotates once.

local core         = require("apisix.core")
local plugin       = require("apisix.plugin")
local resty_random = require("resty.random")
local state        = require("apisix.session_ticket.state")
local record       = require("apisix.plugins.ssl-session-ticket.record")
local ngx          = ngx
local type         = type
local ipairs       = ipairs
local tonumber     = tonumber
local str_sub      = string.sub


local POLICY_DIR = "/ssl_session_ticket/policy/"
-- a registration lives as long as its node keeps the lease alive
local POLICY_TTL = 30
local KEEPALIVE_INTERVAL = 10
-- the period of the rounds, much shorter than any rotation interval
local ROUND_INTERVAL = 5
local CHANGED_ERR = "value changed before overwritten"


local _M = {
    status_name = "generator",
}


--- Whether this node executes the local policy: a traditional or
-- control_plane node backed by etcd, with the HTTP subsystem whose privileged
-- agent runs the rounds.
function _M.executes_policy()
    local local_conf = core.config.local_conf()
    local role = core.table.try_read_attr(local_conf, "deployment", "role")
    if role ~= "traditional" and role ~= "control_plane" then
        return false
    end

    return core.config.type == "etcd"
end


local function new_key(names)
    for _ = 1, 8 do
        local key = resty_random.bytes(state.KEY_SIZE, true)
        if not key then
            return nil, "failed to generate a key"
        end

        if not names[str_sub(key, 1, state.KEY_NAME_SIZE)] then
            return key
        end
    end

    return nil, "failed to generate a key with a unique name"
end


local function key_names(keys)
    local names = {}
    for _, key in ipairs(keys) do
        names[str_sub(key, 1, state.KEY_NAME_SIZE)] = true
    end
    return names
end


-- what the record should become under the local policy, nil if nothing
local function next_record(policy, cur, now, fingerprint)
    if not policy.enabled then
        if cur and not cur.disabled then
            -- the keys stay, the data plane stops using them
            local origin = core.table.clone(cur.origin)
            origin.disabled = true
            origin.policy = fingerprint
            return {keys = cur.keys, origin = origin}, "disabled"
        end

        return nil, "idle"
    end

    if policy.key_source == "external" then
        if not cur then
            -- no automatic key in external mode
            return nil, "idle"
        end

        if cur.source ~= "external" then
            -- generated keys are not external ones: wait for the caller's
            return {
                keys = {},
                origin = {source = "external", disabled = false, policy = fingerprint},
            }, "switched"
        end

        if cur.disabled then
            return {
                keys = cur.keys,
                origin = {source = "external", disabled = false, policy = fingerprint},
            }, "enabled"
        end

        return nil, "idle"
    end

    local gen = policy.generated
    if not cur or cur.source ~= "generated" then
        -- external keys are not generated ones: start a new set
        local key, err = new_key({})
        if not key then
            return nil, nil, err
        end

        return {
            keys = {key},
            origin = {source = "generated", disabled = false, generated_at = now,
                      policy = fingerprint},
        }, cur and "switched" or "initialized"
    end

    local generated_at = tonumber(cur.origin.generated_at) or 0
    if cur.disabled then
        return {
            keys = cur.keys,
            origin = {source = "generated", disabled = false, generated_at = generated_at,
                      policy = fingerprint},
        }, "enabled"
    end

    if now - generated_at >= gen.rotation_interval then
        -- once, however late: catching up on missed periods would push out
        -- keys that tickets still need
        local key, err = new_key(key_names(cur.keys))
        if not key then
            return nil, nil, err
        end

        local keys = {key}
        for i = 1, gen.max_keys - 1 do
            keys[i + 1] = cur.keys[i]
        end

        return {
            keys = keys,
            origin = {source = "generated", disabled = false, generated_at = now,
                      policy = fingerprint},
        }, "rotated"
    end

    if #cur.keys > gen.max_keys then
        local keys = {}
        for i = 1, gen.max_keys do
            keys[i] = cur.keys[i]
        end

        return {
            keys = keys,
            origin = {source = "generated", disabled = false, generated_at = generated_at,
                      policy = fingerprint},
        }, "truncated"
    end

    return nil, "idle"
end


--- One round, as of `now` (seconds).
--
-- @tparam table policy the local policy, see record.policy
-- @tparam number now the time of the round
-- @treturn string|nil "idle", "initialized", "rotated", "truncated",
-- "disabled", "enabled", "switched", or "lost" when another writer changed
-- the record first (the next round reads it again)
-- @treturn string|nil the error; nothing is written on error
-- @treturn number|nil `origin.generated_at` of the record the round ends with
function _M.round(policy, now)
    local res, err = core.etcd.get(record.etcd_key)
    if not res then
        return nil, "failed to read the record: " .. err
    end

    local value, mod_revision
    if res.status == 200 then
        value = res.body.node.value
        mod_revision = res.body.node.modifiedIndex
    elseif res.status == 404 then
        mod_revision = 0
    else
        return nil, "failed to read the record, status: " .. res.status
    end

    local cur
    if value ~= nil then
        cur, err = record.parse(value)
        if not cur then
            -- never overwrite what this node cannot read: its own keyring or
            -- configuration may be the wrong one
            return nil, "the current record can not be used: " .. err
        end
    end

    local fingerprint = record.policy_fingerprint(policy)
    local target, outcome, gen_err = next_record(policy, cur, now, fingerprint)
    local generated_at = cur and cur.source == "generated" and cur.origin.generated_at or nil
    if not target then
        if gen_err then
            return nil, gen_err
        end
        return outcome, nil, generated_at
    end

    local new_value
    new_value, err = record.build(target.keys, target.origin)
    if not new_value then
        return nil, err
    end

    local ok, set_err = core.etcd.atomic_set(record.etcd_key, new_value, nil, mod_revision)
    if not ok then
        if set_err == CHANGED_ERR then
            return "lost", nil, generated_at
        end

        return nil, "failed to write the record: " .. set_err
    end

    return outcome, nil, target.origin.generated_at
end


local registration = {}


-- keep a lease-backed registration of the policy fingerprint of this node
local function register(policy, fingerprint, now)
    if registration.lease_id and registration.fingerprint == fingerprint then
        if now - registration.at < KEEPALIVE_INTERVAL then
            return true
        end

        local res = core.etcd.keepalive(registration.lease_id)
        local ttl = res and type(res.body) == "table" and type(res.body.result) == "table"
                    and tonumber(res.body.result.TTL)
        if ttl and ttl > 0 then
            registration.at = now
            return true
        end
        -- the lease is gone (e.g. etcd was unreachable for too long)
    end

    local res, err = core.etcd.set(POLICY_DIR .. core.id.get(), {
        fingerprint = fingerprint,
        enabled = policy.enabled,
        key_source = policy.key_source,
        rotation_interval = policy.generated.rotation_interval,
        max_keys = policy.generated.max_keys,
    }, POLICY_TTL)
    if not res then
        registration.lease_id = nil
        return nil, err
    end

    registration.lease_id = res.body.lease_id
    registration.fingerprint = fingerprint
    registration.at = now
    return true
end


--- Whether the live nodes executing the policy disagree with `fingerprint`.
--
-- @treturn boolean|nil true when they do, nil on error
-- @treturn string the description of the conflict, or the error
function _M.policy_conflict(fingerprint)
    local res, err = core.etcd.get(POLICY_DIR, true)
    if not res then
        return nil, "failed to read the policies of the nodes: " .. err
    end

    if res.status == 404 then
        return false
    end

    local items = res.body.list or (res.body.node and res.body.node.nodes) or {}
    -- the entry of this node may still be the one of its previous
    -- configuration, it never conflicts with itself
    local own = "/" .. core.id.get()
    local nodes, different = 0, 0
    local seen = {}
    local kinds = 0
    for _, item in ipairs(items) do
        local fp = type(item.value) == "table" and item.value.fingerprint
        if fp and type(item.key) == "string" and str_sub(item.key, -#own) ~= own then
            nodes = nodes + 1
            if fp ~= fingerprint then
                different = different + 1
            end
            if not seen[fp] then
                seen[fp] = true
                kinds = kinds + 1
            end
        end
    end

    if different == 0 then
        return false
    end

    if not seen[fingerprint] then
        kinds = kinds + 1
    end

    return true, "the nodes executing the policy have " .. kinds .. " different "
                 .. "plugin_attr.ssl-session-ticket configurations (" .. different
                 .. " of " .. nodes .. " other registered nodes differ from this one)"
end


local last_report = {}


local function report(executes, st, err, generated_at, now)
    local status = {
        executes = executes,
        state = st,
        error = state.truncate_error(err),
        last_generated_at = generated_at,
        at = now,
    }

    if st ~= last_report.state or err ~= last_report.err then
        if st == "conflict" then
            core.log.warn("pause the TLS session ticket keys: ", err)
        elseif st == "failed" then
            core.log.error("the TLS session ticket generator failed: ", err)
        elseif last_report.state == "conflict" or last_report.state == "failed" then
            core.log.warn("the TLS session ticket generator is back to ", st)
        end
        last_report.state = st
        last_report.err = err
    end

    if generated_at == nil and st ~= "ok" and st ~= "idle" then
        status.last_generated_at = last_report.generated_at
    end
    last_report.generated_at = status.last_generated_at

    local ok, set_err = state.set_status(_M.status_name, status)
    if not ok then
        core.log.error("failed to save the TLS session ticket generator status: ", set_err)
    end
end


--- One complete pass as of `now`: register the policy of this node, check
-- that the other nodes agree, run a round and save the status.
function _M.run(now)
    local policy, err = record.policy()
    if not policy then
        report(false, "failed", err, nil, now)
        return
    end

    local executes = policy.enabled and policy.key_source == "generated"
    if not policy.enabled and plugin.plugin_metadata(record.name) == nil then
        -- nothing to enforce and nothing to agree on: a node that does not
        -- use the feature does not touch etcd for it
        report(executes, "idle", nil, nil, now)
        return
    end

    local fingerprint = record.policy_fingerprint(policy)

    local ok, reg_err = register(policy, fingerprint, now)
    if not ok then
        report(executes, "failed", "failed to register the policy of this node: " .. reg_err,
               nil, now)
        return
    end

    local conflict, desc = _M.policy_conflict(fingerprint)
    if conflict == nil then
        report(executes, "failed", desc, nil, now)
        return
    end

    if conflict then
        report(executes, "conflict", desc, nil, now)
        return
    end

    local outcome, round_err, generated_at = _M.round(policy, now)
    if not outcome then
        report(executes, "failed", round_err, nil, now)
        return
    end

    if outcome ~= "idle" and outcome ~= "lost" then
        core.log.info("the TLS session ticket keys are ", outcome)
    end

    report(executes, executes and "ok" or "idle", nil, generated_at, now)
end


local next_round = 0


--- The periodic job of the privileged agent.
function _M.tick()
    local now = ngx.time()
    if now < next_round then
        return
    end
    next_round = now + ROUND_INTERVAL

    _M.run(now)
end


return _M
