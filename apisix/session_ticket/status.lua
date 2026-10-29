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

--- Read-only status of the business TLS session ticket keys on this node,
-- served by the Control API as `GET /v1/tls_session_ticket`.
--
-- It only reads the neutral state with a bounded number of reads: it loads no
-- plugin, calls nothing of the SSL layer, does no I/O and changes nothing. It
-- never returns key material, key names or anything derived from them.
--
-- @module apisix.session_ticket.status

local core    = require("apisix.core")
local state   = require("apisix.session_ticket.state")
local ngx     = ngx
local type    = type
local next    = next
local pairs   = pairs
local ipairs  = ipairs
local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable
local math_floor = math.floor
local os_date = os.date
local str_match = string.match
local get_method = ngx.req.get_method


-- the status that the built-in generator saves in the state
local GENERATOR = "generator"

-- the public example keyring of conf/config.yaml.example and the defaults
local DEFAULT_KEYRING = {
    qeddd145sfvddff3 = true,
    edd1c9f0985e76a2 = true,
}

-- the higher in this list, the more important the reason of a degraded status
local reason_rank = {
    invalid_state = 1,
    module_not_active = 2,
    apply_failed = 3,
    worker_lag = 4,
}

-- the reasons of the errors of the runtime, any other one is "apply_failed"
local error_reasons = {
    not_supported = "module_not_active",
    not_registered = "module_not_active",
    no_context = "invalid_state",
}

-- a process counts as failed rather than pending, as pending rather than applied
local outcome_rank = {
    applied = 1,
    pending = 2,
    failed = 3,
}

-- the target and the worker records are read for one control record,
-- a bounded number of times
local READ_ATTEMPTS = 3


local _M = {}


--- Security warnings about the keyring that protects the keys in etcd.
--
-- They are reported whatever the status is, and do not change it.
--
-- @treturn table array of "encryption_disabled" or "default_keyring"
function _M.keyring_warnings()
    if core.config.type ~= "etcd" then
        -- standalone keeps the record in the local configuration
        return {}
    end

    local local_conf = core.config.local_conf()
    if not core.table.try_read_attr(local_conf, "apisix", "data_encryption",
                                    "enable_encrypt_fields") then
        return {"encryption_disabled"}
    end

    local ring = core.table.try_read_attr(local_conf, "apisix", "data_encryption", "keyring")
    if type(ring) == "string" then
        ring = {ring}
    end

    if type(ring) == "table" then
        for _, k in ipairs(ring) do
            if DEFAULT_KEYRING[k] then
                return {"default_keyring"}
            end
        end
    end

    return {}
end


-- whether this node allows its business TLS listeners to use the shared keys:
-- `apisix.ssl.ssl_session_tickets`, true unless set to false
local function local_switch()
    local local_conf = core.config.local_conf()
    return core.table.try_read_attr(local_conf, "apisix", "ssl", "ssl_session_tickets") ~= false
end


local function enabled_subsystems()
    local local_conf = core.config.local_conf()
    local mode = core.table.try_read_attr(local_conf, "apisix", "proxy_mode") or "http"
    return {
        http = mode == "http" or mode == "http&stream",
        stream = mode == "stream" or mode == "http&stream",
    }
end


local function iso_time(t)
    return os_date("!%Y-%m-%dT%H:%M:%SZ", math_floor(t))
end


local function zero_workers()
    return {total = 0, applied = 0, pending = 0, failed = 0}
end


-- the built-in generator runs in the privileged agent of the traditional and
-- control_plane nodes backed by etcd, which only the HTTP subsystem has
local function generator_status(local_conf, subsystems)
    local role = core.table.try_read_attr(local_conf, "deployment", "role")
    if (role ~= "traditional" and role ~= "control_plane") or core.config.type ~= "etcd"
       or not subsystems.http
    then
        return core.json.null
    end

    local st = state.get_status(GENERATOR)
    if type(st) ~= "table" then
        local attr = core.table.try_read_attr(local_conf, "plugin_attr", "ssl-session-ticket")
        local executes = type(attr) == "table" and attr.enabled == true
                         and (attr.key_source or "generated") == "generated"
        return {executes = executes, state = "idle", last_generated_at = core.json.null,
                error = core.json.null}
    end

    return {
        executes = st.executes == true,
        state = st.state,
        last_generated_at = type(st.last_generated_at) == "number"
                            and iso_time(st.last_generated_at) or core.json.null,
        error = type(st.error) == "string" and st.error or core.json.null,
    }
end


local function error_reason(err)
    local code = type(err) == "string" and str_match(err, "^[%w_]+")
    return code and error_reasons[code] or "apply_failed"
end


-- the failure that a worker record reports, if any, and its reason
local function record_failure(rec)
    if type(rec.error) == "string" then
        return rec.error, error_reason(rec.error)
    end

    for _, ctx in ipairs(type(rec.contexts) == "table" and rec.contexts or {}) do
        if type(ctx) == "table" and not ctx.ok then
            local err = type(ctx.error) == "string" and ctx.error or "failed"
            return "context " .. tostring(ctx.id) .. ": " .. err, error_reason(err)
        end
    end
end


-- "applied", "pending" or "failed", and the reason and error of the last two
local function record_outcome(rec, snap)
    local failure, reason = record_failure(rec)
    if failure then
        return "failed", reason, failure
    end

    if rec.exiting or type(rec.contexts) ~= "table" or #rec.contexts == 0 then
        -- a worker that shuts down has turned every context off for good and
        -- takes no new connection; without any context there is nothing to do
        return "applied"
    end

    if rec.applied_version == snap.version and rec.applied_gate == snap.gate then
        return "applied"
    end

    return "pending", "worker_lag"
end


-- the target and the worker records, as of one version of the control record
local function read_consistent()
    for _ = 1, READ_ATTEMPTS do
        local before, err = state.read_control()
        if not before then
            return nil, err
        end

        local snap
        snap, err = state.read()
        if not snap and err ~= "inconsistent" then
            return nil, err
        end

        if snap then
            local records
            records, err = state.worker_records()
            if not records then
                return nil, err
            end

            local after = state.read_control()
            if after and after.version == before.version and after.gate == before.gate
               and snap.version == after.version and snap.gate == after.gate
            then
                return snap, records
            end
        end
    end

    return nil, "inconsistent"
end


local function off_reason(enabled, snap)
    if not enabled then
        return "local_switch_off"
    end

    if snap.gate == "ready" and snap.origin and snap.origin.disabled then
        return "disabled_by_policy"
    end

    -- no keys, or no source has confirmed any yet, e.g. the Plugin is not
    -- enabled in this configuration
    return "empty_keys"
end


--- Build the status.
--
-- @treturn number 200
-- @treturn table the status
function _M.get()
    local enabled = local_switch()
    local subsystems = enabled_subsystems()
    local body = {
        status = "degraded",
        reason = core.json.null,
        enabled = enabled,
        key_count = 0,
        effective_key_count = core.json.null,
        fully_applied = false,
        version = core.json.null,
        source = core.json.null,
        source_version = core.json.null,
        updated_at = core.json.null,
        updated_at_sec_ago = core.json.null,
        workers = zero_workers(),
        subsystems = {},
        generator = generator_status(core.config.local_conf(), subsystems),
        warnings = setmetatable(_M.keyring_warnings(), core.json.array_mt),
        last_apply_error = core.json.null,
    }

    local reason, reason_err
    local function degrade(r, err)
        if not reason or reason_rank[r] < reason_rank[reason] then
            reason = r
            reason_err = err
        end
    end

    local record_err = state.worker_record_failure()
    if record_err then
        degrade("invalid_state", record_err)
    end

    local snap, records = read_consistent()
    if not snap then
        local err = records
        if err == "inconsistent" then
            degrade("worker_lag", "the state kept changing while being read")
        elseif err == "control record unavailable" then
            degrade("invalid_state", err)
        else
            -- e.g. no shared dict without APISIX Runtime
            degrade("module_not_active", err)
        end

        -- nothing can be told about the workers either
        for _, name in ipairs(state.SUBSYSTEMS) do
            body.subsystems[name] = {
                applicable = false,
                status = subsystems[name] and "degraded" or "off",
                reason = subsystems[name] and reason or core.json.null,
                contexts = 0,
                workers = zero_workers(),
                draining = zero_workers(),
            }
        end

        body.reason = reason
        body.last_apply_error = state.truncate_error(reason_err) or core.json.null
        return 200, body
    end

    body.version = snap.version
    if snap.origin then
        body.source = snap.origin.source or core.json.null
        body.source_version = snap.origin.revision and tostring(snap.origin.revision)
                              or core.json.null
    end

    if snap.updated_at then
        body.updated_at = iso_time(snap.updated_at)
        local age = math_floor(ngx.now() - snap.updated_at)
        body.updated_at_sec_ago = age > 0 and age or 0
    end

    if snap.gate == "unavailable" or snap.state == "unavailable" then
        degrade("invalid_state", snap.error)
    end

    -- a pending target (no confirmed source yet) is off like an empty one
    local target_on = enabled and snap.gate == "ready" and snap.state == "ready"
                      and #snap.keys > 0
    if target_on then
        body.key_count = #snap.keys
    end

    -- A process refreshes its records as long as it runs. The current
    -- configuration generation is the newest one seen; the processes of an
    -- older one are draining.
    local now = ngx.now()
    local generation = state.process_generation() or 0
    if snap.generation > generation then
        generation = snap.generation
    end

    local live = {}
    for _, rec in ipairs(records) do
        if type(rec.seen_at) == "number" and now - rec.seen_at < state.WORKER_LIVE_TTL then
            core.table.insert(live, rec)
            local gen = tonumber(rec.generation) or 0
            if gen > generation then
                generation = gen
            end
        end
    end

    -- the node counts each process once, whatever the subsystems it serves
    local slot_pids = {}
    for _, rec in ipairs(live) do
        if (tonumber(rec.generation) or 0) == generation then
            slot_pids[rec.slot] = rec.pid
        end
    end

    local processes = {}
    local function note(process, outcome)
        local prev = processes[process]
        if not prev or outcome_rank[outcome] > outcome_rank[prev] then
            processes[process] = outcome
        end
    end

    local applicable = false
    for _, name in ipairs(state.SUBSYSTEMS) do
        local sub = {
            applicable = false,
            status = "off",
            reason = core.json.null,
            contexts = 0,
            workers = zero_workers(),
            draining = zero_workers(),
        }
        body.subsystems[name] = sub

        if subsystems[name] then
            local sub_reason, sub_err
            local function sub_degrade(r, err)
                if not sub_reason or reason_rank[r] < reason_rank[sub_reason] then
                    sub_reason = r
                    sub_err = err
                end
            end

            -- all the workers of a configuration generation have the same
            -- listeners
            local reported = {}
            for _, rec in ipairs(live) do
                if rec.subsystem == name and (tonumber(rec.generation) or 0) == generation then
                    reported[rec.slot] = true
                    local n = type(rec.contexts) == "table" and #rec.contexts or 0
                    if n > sub.contexts then
                        sub.contexts = n
                    end
                end
            end
            sub.applicable = sub.contexts > 0

            for _, rec in ipairs(live) do
                if rec.subsystem == name then
                    local draining = (tonumber(rec.generation) or 0) < generation
                    local workers = draining and sub.draining or sub.workers
                    local outcome, r, err = record_outcome(rec, snap)
                    workers.total = workers.total + 1
                    workers[outcome] = workers[outcome] + 1
                    note(rec.pid, outcome)
                    if r then
                        sub_degrade(r, err or ((draining and "a draining" or "a")
                                               .. " worker of the " .. name .. " subsystem"
                                               .. " has not applied the current target yet"))
                    end
                end
            end

            if not next(reported) then
                sub_degrade("module_not_active", "nothing applies the keys to the "
                                                 .. name .. " listeners")

            elseif sub.applicable then
                for slot = 0, ngx.worker.count() - 1 do
                    if not reported[slot] then
                        sub.workers.total = sub.workers.total + 1
                        sub.workers.pending = sub.workers.pending + 1
                        note(slot_pids[slot] or "slot " .. slot, "pending")
                        sub_degrade("worker_lag", "the worker " .. slot .. " of the " .. name
                                                  .. " subsystem has not reported yet")
                    end
                end
            end

            if sub_reason then
                sub.status = "degraded"
                sub.reason = sub_reason
                degrade(sub_reason, sub_err)

            elseif sub.applicable then
                applicable = true
                if target_on then
                    sub.status = "ok"
                else
                    sub.reason = off_reason(enabled, snap)
                end
            end
        end
    end

    for _, outcome in pairs(processes) do
        body.workers.total = body.workers.total + 1
        body.workers[outcome] = body.workers[outcome] + 1
    end

    if reason then
        body.reason = reason
        if reason_err then
            body.last_apply_error = state.truncate_error(reason_err)
        end
        return 200, body
    end

    -- every process has converged, the draining ones included
    body.fully_applied = true
    body.effective_key_count = applicable and body.key_count or 0
    if target_on and applicable then
        body.status = "ok"
    else
        -- without any business TLS context, nothing uses the keys
        body.status = "off"
        if not target_on then
            body.reason = off_reason(enabled, snap)
        end
    end

    return 200, body
end


--- Serve the status from a bare `location`, as the Stream-only control
-- server does.
function _M.http_handler()
    if get_method() ~= "GET" then
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end

    local code, body = _M.get()
    core.response.set_header("Content-Type", "application/json")
    return core.response.exit(code, body)
end


return _M
