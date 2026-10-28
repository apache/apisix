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
local ipairs  = ipairs
local tostring = tostring
local setmetatable = setmetatable
local math_floor = math.floor
local os_date = os.date
local get_method = ngx.req.get_method


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


-- whether this node allows its business TLS listeners to use the shared keys
local function local_switch()
    local local_conf = core.config.local_conf()
    return core.table.try_read_attr(local_conf, "apisix", "ssl", "ssl_session_tickets") == true
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


--- Build the status.
--
-- @treturn number 200
-- @treturn table the status
function _M.get()
    local enabled = local_switch()
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
        -- filled by the nodes running the built-in generator
        generator = core.json.null,
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

    -- state.read checks the control record before and after the snapshot and
    -- retries a bounded number of times
    local snap, err = state.read()
    if not snap then
        if err == "inconsistent" then
            degrade("worker_lag", "the state kept changing while being read")
        elseif err == "control record unavailable" then
            degrade("invalid_state", err)
        else
            -- e.g. no shared dict without APISIX Runtime
            degrade("module_not_active", err)
        end

    else
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
        elseif snap.gate ~= "ready" then
            degrade("worker_lag", snap.error or "no state has been published yet")
        end

        if enabled and snap.state == "ready" then
            body.key_count = #snap.keys
        end
    end

    local record_err = state.worker_record_failure()
    if record_err then
        degrade("invalid_state", record_err)
    end

    -- The consumers of the SSL layer report through their worker records, and
    -- aggregating them belongs to the consumer side. Until it is there, no
    -- business context is known to have applied anything: never report ok or
    -- off for an enabled subsystem.
    local subsystems = enabled_subsystems()
    for _, name in ipairs(state.SUBSYSTEMS) do
        local sub = {
            applicable = false,
            status = "off",
            reason = core.json.null,
            contexts = 0,
            workers = zero_workers(),
        }

        if subsystems[name] then
            sub.status = "degraded"
            sub.reason = "module_not_active"
        end

        body.subsystems[name] = sub
    end
    degrade("module_not_active", "the SSL layer does not consume the keys")

    if reason then
        body.reason = reason
        if reason_err then
            body.last_apply_error = state.truncate_error(reason_err)
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
