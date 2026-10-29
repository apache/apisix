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

--- Consumer of the business TLS session ticket keys.
--
-- Every worker process applies the target of the neutral state to the SSL
-- contexts of the business TLS listeners of its subsystem, the ones the nginx
-- template marks with `apisix_ssl_session_ticket_takeover on`: once when it
-- starts, then every second, and before a handshake whenever the target has
-- changed. Those contexts start with tickets off, and only get them on once a
-- complete non-empty set of keys is installed. When the worker starts to shut
-- down, it turns them all off for good. It reads the neutral state only:
-- never the plugin, its metadata or etcd.
--
-- @module apisix.ssl.session_ticket

local core    = require("apisix.core")
local state   = require("apisix.session_ticket.state")
local timers  = require("apisix.timers")
local process = require("ngx.process")
local ngx     = ngx
local type    = type
local pcall   = pcall
local ipairs  = ipairs
local tostring = tostring
local require = require
local subsystem = ngx.config.subsystem


-- the Lua API of the takeover in apisix-nginx-module, absent in older runtimes
local ticket
do
    local ok, mod = pcall(require, "resty.apisix.ssl_session_ticket")
    if ok and type(mod) == "table" then
        ticket = mod
    end
end

local TIMER_NAME = "ssl#session_ticket"
-- how often an unchanged failure is logged again
local FAILURE_LOG_INTERVAL = 60
-- how often an unchanged worker record is refreshed, well within
-- state.WORKER_LIVE_TTL
local REFRESH_INTERVAL = 3
-- a timer that only matters when it runs early: nginx runs the pending
-- timers at once when the worker starts to shut down
local EXIT_HOOK_INTERVAL = 3600


local _M = {}


--- Whether the business TLS listeners of this node may use the shared keys:
-- `apisix.ssl.ssl_session_tickets`, true unless set to false.
function _M.local_switch()
    local local_conf = core.config.local_conf()
    return core.table.try_read_attr(local_conf, "apisix", "ssl", "ssl_session_tickets") ~= false
end


-- what this worker has done
local applied = {
    -- the target (a version goes through the "pending" gate before the
    -- "ready" one) that every context has applied, nil while a failure is
    -- not resolved
    version = nil,
    gate = nil,
    -- the target last tried, so that a handshake does not retry a failure
    -- each time
    tried_version = nil,
    tried_gate = nil,
    contexts = {},
    error = nil,
    at = nil,
    -- the worker shuts down: every context is off for good
    exiting = false,
}
-- whether the record of the worker is out of date
local dirty = true


local function apply_context(ctx, off, keys)
    if not ctx.registered then
        -- the runtime could not register the callback of this context: it
        -- stays off, whatever the target
        ticket.revoke_keys(ctx.id)
        return false, "not_registered"
    end

    if off then
        -- stop issuing and accepting shared tickets before removing the keys
        local ok, err = ticket.disable_tickets(ctx.id)
        if ok then
            ok, err = ticket.revoke_keys(ctx.id)
        end
        return ok and true or false, err
    end

    -- the complete set first, tickets on only once it is there
    local ok, err = ticket.set_keys(ctx.id, keys)
    if ok then
        ok, err = ticket.enable_tickets(ctx.id)
    end

    if not ok then
        -- whatever failed, this context must not use shared tickets
        ticket.revoke_keys(ctx.id)
        return false, err
    end

    return true
end


--- Apply the current target to all the contexts of this worker.
--
-- Every target is applied and recorded, an off one included: a "pending"
-- target (no source has confirmed any keys yet) or an "unavailable" one is
-- off. A failure is retried by the next round.
--
-- @treturn boolean|nil true when every context has applied it
-- @treturn string|nil the error
function _M.reconcile()
    if not ticket then
        return nil, "not_supported"
    end

    if not applied.exiting then
        local ctl = state.read_control()
        if ctl and applied.version == ctl.version and applied.gate == ctl.gate then
            return true
        end
    end

    local snap, read_err = state.read()
    local off = true
    if snap and not applied.exiting then
        off = not (_M.local_switch() and snap.gate == "ready" and snap.state == "ready"
                   and #snap.keys > 0)
    end

    applied.tried_version = snap and snap.version
    applied.tried_gate = snap and snap.gate
    dirty = true

    local list, err = ticket.contexts()
    if not list then
        applied.version = nil
        applied.gate = nil
        applied.contexts = {}
        applied.error = err
        return nil, err
    end

    local results = core.table.new(#list, 0)
    local failure
    for i, ctx in ipairs(list) do
        local ok, ctx_err = apply_context(ctx, off, snap and snap.keys)
        results[i] = {id = ctx.id, ok = ok, error = ctx_err}
        if not ok and not failure then
            failure = "context " .. tostring(ctx.id) .. ": " .. tostring(ctx_err)
        end
    end

    applied.contexts = results
    applied.error = nil
    if failure or not snap then
        -- no safe state at all is off too, but not a target
        applied.version = nil
        applied.gate = nil
        return false, failure or read_err
    end

    applied.version = snap.version
    applied.gate = snap.gate
    applied.at = ngx.now()
    return true
end


local reporting = false
local last_report_at = 0
local last_report_err
local last_report_err_at = 0


local function report()
    if reporting then
        -- writing the record may wait for the lock: the writer in progress
        -- writes it again
        dirty = true
        return
    end

    local identity = state.process_identity(subsystem)
    if not identity then
        -- the runtime has no process identity API
        return
    end

    reporting = true
    while true do
        local now = ngx.now()
        if not dirty and now - last_report_at < REFRESH_INTERVAL then
            break
        end

        dirty = false
        local ctl = state.read_control()
        local ok, err = state.put_worker_record(identity, {
            target_version = ctl and ctl.version,
            applied_version = applied.version,
            applied_gate = applied.gate,
            contexts = applied.contexts,
            applied_at = applied.at,
            error = applied.error,
            exiting = applied.exiting,
        })
        if not ok then
            dirty = true
            if err ~= last_report_err or now - last_report_err_at >= FAILURE_LOG_INTERVAL then
                core.log.error("failed to record the TLS session ticket progress: ", err)
                last_report_err = err
                last_report_err_at = now
            end
            break
        end

        last_report_at = now
        last_report_err = nil
    end
    reporting = false
end


local last_apply_err
local last_apply_err_at = 0


local function tick()
    local ok, err = _M.reconcile()
    if ok then
        last_apply_err = nil
    else
        local now = ngx.now()
        if err ~= last_apply_err or now - last_apply_err_at >= FAILURE_LOG_INTERVAL then
            -- the state changed while being read: off until the next round
            local log = err == "inconsistent" and core.log.warn or core.log.error
            log("failed to apply the TLS session ticket keys: ", err)
            last_apply_err = err
            last_apply_err_at = now
        end
    end

    report()
end


local function on_exit_hook(premature)
    if not premature then
        return
    end

    -- No new connection reaches this worker any more. Turn every context off
    -- for good, so that nothing of the worker keeps using keys that may be
    -- revoked meanwhile, and say so until the process is gone.
    applied.exiting = true
    tick()
end


--- Called in the ClientHello phase of the business TLS listeners.
--
-- Applies a changed target first, then aligns the options of the current
-- connection with its context: an SSL object copies them only when it is
-- created.
function _M.client_hello()
    if not ticket then
        return
    end

    if not applied.exiting then
        local ctl = state.read_control()
        if ctl and (ctl.version ~= applied.tried_version or ctl.gate ~= applied.tried_gate) then
            _M.reconcile()
        end
    end

    -- "not_marked" for a listener that is not a business one
    ticket.sync_connection()
end


function _M.init_worker()
    if not ticket then
        return
    end

    local ptype = process.type()
    if ptype ~= "worker" and ptype ~= "single" then
        -- the privileged agent has no business listener
        return
    end

    tick()
    timers.register_timer(TIMER_NAME, tick)

    local ok, err = ngx.timer.every(EXIT_HOOK_INTERVAL, on_exit_hook)
    if not ok then
        core.log.error("failed to create the exit hook of the TLS session ticket keys: ", err)
    end
end


--- Called when the worker process exits: its records go with it, the one of
-- the Stream subsystem too, which has no such hook.
function _M.exit_worker()
    for _, name in ipairs(state.SUBSYSTEMS) do
        local identity = state.process_identity(name)
        if identity then
            state.delete_worker_record(identity)
        end
    end
end


return _M
