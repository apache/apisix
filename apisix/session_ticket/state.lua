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

--- Neutral state of the business TLS session ticket keys.
--
-- Source adapters (today the `ssl-session-ticket` plugin) publish complete
-- snapshots here; the SSL layer and the Control API only read them. The state
-- lives in the `tls-session-ticket` dictionary of the main-level `lua {}`
-- block, which apisix-nginx-module injects into both the HTTP and the Stream
-- subsystems, so all the Lua VMs of a node share it. Without that block the
-- dictionary is missing and the feature is unavailable: there is no fallback
-- to two isolated dictionaries.
--
-- This module must not require any plugin or the SSL layer.
--
-- Keys of the dictionary:
--
--  * `epoch`: random run generation of the dictionary, created once.
--  * `ctl`: fixed-length control record. It is created once and then only
--    updated in place, so closing the gate never needs a new allocation. It
--    holds the gate, the local sequence of the current target, the record
--    revision watermark and the config generation.
--  * `lock`, `lock_at`: numeric lock serializing the writers of all the
--    processes, also updated in place.
--  * `snap`: the complete snapshot of the current target, stored with
--    safe_set (never evicting) and without TTL.
--  * `w:<subsystem>:<lane>:<slot>`: bounded per-process records of the
--    consumers, see put_worker_record.
--  * `wmax`, `wfail_at`, `wfail_code`: bookkeeping of those records.
--
-- @module apisix.session_ticket.state

local require       = require
local core          = require("apisix.core")
local resty_random  = require("resty.random")
local str_util      = require("resty.string")
local ngx           = ngx
local type          = type
local setmetatable  = setmetatable
local pcall         = pcall
local tostring      = tostring
local tonumber      = tonumber
local ipairs        = ipairs
local math_floor    = math.floor
local str_format    = string.format
local str_sub       = string.sub
local str_rep       = string.rep
local str_byte      = string.byte
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64


local _M = {
    DICT_NAME = "tls-session-ticket",
    -- size of one key: name(16) | HMAC-SHA256(32) | AES-256-CBC(32)
    KEY_SIZE = 80,
    KEY_NAME_SIZE = 16,
    -- upper bound of a snapshot, the same as the runtime accepts
    MAX_KEYS = 256,
    SUBSYSTEMS = {"http", "stream"},
    -- the current config generation plus one draining generation
    WORKER_LANES = 2,
    -- one slot per worker process plus the privileged agent
    MAX_WORKER_SLOTS = 1025,
    MAX_CONTEXTS = 16,
    MAX_ERROR_LEN = 128,
    MAX_CONTEXT_ERROR_LEN = 32,
    -- padded size of a worker record: with the key and the node header it
    -- still fits a 2k slab slot, see nginx_config.meta.lua_shared_dict
    WORKER_RECORD_SIZE = 1920,
    -- a record that has not been refreshed for this long belongs to a
    -- process that is gone, its slot can be taken over
    WORKER_LIVE_TTL = 10,
}


local EPOCH_KEY = "epoch"
local CTL_KEY = "ctl"
local LOCK_KEY = "lock"
local LOCK_AT_KEY = "lock_at"
local SNAP_KEY = "snap"
local WMAX_KEY = "wmax"
local WFAIL_AT_KEY = "wfail_at"
local WFAIL_CODE_KEY = "wfail_code"

-- a lock held for longer than this is left over by a process that died in
-- the (non-yielding) critical section
local LOCK_STALE = 5
local LOCK_ATTEMPTS = 1000
local READ_ATTEMPTS = 3

local GATE_NONE = "N"
local GATE_PENDING = "P"
local GATE_UNAVAILABLE = "U"
local GATE_READY = "R"

local gate_names = {
    [GATE_NONE] = "none",
    [GATE_PENDING] = "pending",
    [GATE_UNAVAILABLE] = "unavailable",
    [GATE_READY] = "ready",
}

local ERR_NONE = 0
local ERR_SNAPSHOT = 1
local ERR_GENERATION = 2

local err_msgs = {
    [ERR_SNAPSHOT] = "failed to store the snapshot",
    [ERR_GENERATION] = "waiting for the source of the new configuration generation",
}

local WFAIL_NO_MEMORY = 1
local WFAIL_SLOT_BUSY = 2
local WFAIL_INVALID = 3

local wfail_msgs = {
    [WFAIL_NO_MEMORY] = "no memory for the worker record",
    [WFAIL_SLOT_BUSY] = "no free worker record slot",
    [WFAIL_INVALID] = "invalid worker record",
}

-- version, gate, absent flag, sequence, revision watermark, generation, error
-- code and content tag, always CTL_LEN bytes long
local CTL_FORMAT = "1%s%s%016d%020d%010d%04d%16s"
local CTL_LEN = 69
local EMPTY_TAG = str_rep("0", 16)
-- the largest integers a Lua number holds exactly, within the field widths
local MAX_SEQ = 2 ^ 53 - 1
local MAX_REVISION = 2 ^ 53 - 1
local MAX_GENERATION = 1e10 - 1

local state_names = {
    ready = true,
    empty = true,
    unavailable = true,
}


local function get_dict()
    return ngx.shared[_M.DICT_NAME]
end


local function now()
    -- read at call time on purpose, so that tests can travel in time
    return ngx.now()
end


local function encode_ctl(ctl)
    return str_format(CTL_FORMAT, ctl.gate, ctl.absent and "1" or "0", ctl.seq,
                      ctl.revision, ctl.generation, ctl.err, ctl.tag)
end


local function decode_ctl(raw)
    if type(raw) ~= "string" or #raw ~= CTL_LEN or str_byte(raw, 1) ~= 49 then
        return nil
    end

    local ctl = {
        gate = str_sub(raw, 2, 2),
        absent = str_sub(raw, 3, 3) == "1",
        seq = tonumber(str_sub(raw, 4, 19)),
        revision = tonumber(str_sub(raw, 20, 39)),
        generation = tonumber(str_sub(raw, 40, 49)),
        err = tonumber(str_sub(raw, 50, 53)),
        tag = str_sub(raw, 54, 69),
    }
    if not (gate_names[ctl.gate] and ctl.seq and ctl.revision and ctl.generation
            and ctl.err) then
        return nil
    end

    return ctl
end


local function store_ctl(dict, ctl)
    -- the record keeps its length, so this is an in-place update which cannot
    -- run out of memory; safe_set makes sure nothing is evicted otherwise
    return dict:safe_set(CTL_KEY, encode_ctl(ctl))
end


local function is_uint(v, max)
    return type(v) == "number" and v >= 0 and v <= max and v == math_floor(v)
end


--- Pre-create the epoch, the control record and the lock.
--
-- It runs in the init phase of both subsystems and again in init_worker, but
-- only the first successful call creates anything: the epoch (run generation
-- of the dictionary) is established exactly once per dictionary lifetime and
-- survives normal reloads like the dictionary itself.
--
-- @treturn boolean|nil true on success
-- @treturn string|nil the error
function _M.init()
    local dict = get_dict()
    if not dict then
        return nil, "shared dict '" .. _M.DICT_NAME .. "' not found"
    end

    local epoch = dict:get(EPOCH_KEY)
    if not epoch then
        local bytes = resty_random.bytes(4, true) or resty_random.bytes(4)
        dict:safe_add(EPOCH_KEY, str_util.to_hex(bytes))
    end

    dict:safe_add(LOCK_KEY, 0)
    dict:safe_add(LOCK_AT_KEY, 0)
    dict:safe_add(WMAX_KEY, 0)
    dict:safe_add(WFAIL_AT_KEY, 0)
    dict:safe_add(WFAIL_CODE_KEY, 0)
    dict:safe_add(CTL_KEY, encode_ctl({
        gate = GATE_NONE,
        absent = true,
        seq = 0,
        revision = 0,
        generation = 0,
        err = ERR_NONE,
        tag = EMPTY_TAG,
    }))

    for _, key in ipairs({EPOCH_KEY, LOCK_KEY, LOCK_AT_KEY, WMAX_KEY, WFAIL_AT_KEY,
                          WFAIL_CODE_KEY, CTL_KEY}) do
        if dict:get(key) == nil then
            return nil, "failed to pre-create the control records of shared dict '"
                        .. _M.DICT_NAME .. "'"
        end
    end

    return true
end


local process_api
local function get_process_api()
    if process_api == nil then
        -- the process identity API of the runtime (apisix-nginx-module), the
        -- only source of the config generation and of the process slot
        local ok, mod = pcall(require, "resty.apisix.process")
        process_api = ok and type(mod) == "table" and type(mod.get_identity) == "function"
                      and mod or false
    end

    return process_api or nil
end


--- The identity of this process for the given subsystem.
--
-- @treturn table|nil `{subsystem, slot, pid, generation}`, nil when the
-- runtime does not provide the process identity API or outside a worker
-- process (e.g. in the init phase)
function _M.process_identity(subsystem)
    local api = get_process_api()
    if not api then
        return nil
    end

    local ok, id = pcall(api.get_identity)
    if not ok or type(id) ~= "table" or not is_uint(id.generation, MAX_GENERATION)
       or id.generation == 0 or not is_uint(id.slot, _M.MAX_WORKER_SLOTS - 1)
    then
        return nil
    end

    return {
        subsystem = subsystem,
        slot = id.slot,
        pid = id.pid,
        generation = id.generation,
    }
end


--- The config generation of this process, nil when unknown.
function _M.process_generation()
    local id = _M.process_identity(ngx.config.subsystem)
    return id and id.generation
end


local function sleep_or_spin()
    -- ngx.sleep is disabled in a few phases (e.g. init_worker); spinning is
    -- good enough there, the critical section never yields
    pcall(ngx.sleep, 0.001)
end


local function lock(dict)
    for _ = 1, LOCK_ATTEMPTS do
        local v, err = dict:incr(LOCK_KEY, 1)
        if not v then
            return nil, err
        end

        if v == 1 then
            dict:safe_set(LOCK_AT_KEY, now())
            return true
        end

        dict:incr(LOCK_KEY, -1)

        -- Only a process that died inside the critical section, which never
        -- yields, leaves the lock behind. Taking it over is not atomic, but
        -- that race needs such a crash in the first place.
        local at = dict:get(LOCK_AT_KEY)
        if at and at > 0 and now() - at > LOCK_STALE then
            core.log.warn("release the stale lock of shared dict '", _M.DICT_NAME, "'")
            dict:safe_set(LOCK_KEY, 0)
        end

        sleep_or_spin()
    end

    return nil, "timeout"
end


local function unlock(dict)
    dict:safe_set(LOCK_AT_KEY, 0)
    dict:incr(LOCK_KEY, -1)
end


-- run f(dict, ...) with the writer lock held; f must not yield
local function with_lock(f, ...)
    local dict = get_dict()
    if not dict then
        return nil, "shared dict '" .. _M.DICT_NAME .. "' not found"
    end

    if dict:get(CTL_KEY) == nil then
        -- the startup pre-creation failed, retry it before giving up
        local ok, err = _M.init()
        if not ok then
            return nil, err
        end
    end

    local ok, err = lock(dict)
    if not ok then
        return nil, "failed to lock shared dict '" .. _M.DICT_NAME .. "': " .. err
    end

    local pok, res, res_err = pcall(f, dict, ...)
    unlock(dict)

    if not pok then
        return nil, res
    end

    return res, res_err
end


local function truncate(s, max)
    if s == nil then
        return nil
    end

    max = max or _M.MAX_ERROR_LEN
    s = tostring(s)
    if #s > max then
        return str_sub(s, 1, max)
    end

    return s
end
_M.truncate_error = truncate


local function check_candidate(cand)
    if type(cand) ~= "table" then
        return nil, "invalid candidate"
    end

    if not state_names[cand.state] then
        return nil, "invalid candidate state"
    end

    if not is_uint(cand.revision, MAX_REVISION) then
        return nil, "invalid candidate revision"
    end

    if cand.generation ~= nil and not is_uint(cand.generation, MAX_GENERATION) then
        return nil, "invalid candidate generation"
    end

    if cand.state == "ready" then
        if type(cand.keys) ~= "table" or #cand.keys == 0 or #cand.keys > _M.MAX_KEYS then
            return nil, "invalid candidate keys"
        end

        for _, key in ipairs(cand.keys) do
            if type(key) ~= "string" or #key ~= _M.KEY_SIZE then
                return nil, "invalid candidate keys"
            end
        end
    end

    return true
end


-- identifies what a reader of the snapshot would see, so that the same record
-- interpreted differently (e.g. after a reload changed the local policy or the
-- keyring) is not mistaken for a duplicate; it never leaves the dictionary
local function content_tag(cand)
    local parts = {
        cand.state,
        cand.record and "1" or "0",
        cand.source or "",
        cand.disabled and "1" or "0",
        truncate(cand.error) or "",
    }
    if cand.state == "ready" then
        for _, key in ipairs(cand.keys) do
            core.table.insert(parts, key)
        end
    end

    return str_sub(str_util.to_hex(ngx.sha1_bin(core.table.concat(parts, "\0"))), 1, 16)
end


local function encode_snapshot(epoch, seq, cand, published_at)
    local keys = {}
    if cand.state == "ready" then
        for i, key in ipairs(cand.keys) do
            keys[i] = encode_base64(key)
        end
    end

    local origin
    if cand.record then
        origin = {
            source = cand.source,
            disabled = cand.disabled and true or false,
            -- a string, so that the JSON encoder keeps every digit
            revision = str_format("%d", cand.revision),
        }
    end

    return core.json.encode({
        epoch = epoch,
        seq = seq,
        state = cand.state,
        keys = setmetatable(keys, core.json.array_mt),
        updated_at = published_at,
        origin = origin,
        error = truncate(cand.error),
    })
end


local function do_publish(dict, cand, published_at)
    local ctl = decode_ctl(dict:get(CTL_KEY))
    if not ctl then
        return nil, "invalid control record"
    end

    local generation = cand.generation or 0
    if generation < ctl.generation then
        -- a producer of an old config generation must not write back
        return "stale"
    end

    local tag = content_tag(cand)
    local new_generation = generation > ctl.generation
    if not new_generation then
        if cand.revision < ctl.revision then
            return "stale"
        end

        if cand.revision == ctl.revision and ctl.gate == GATE_READY and ctl.tag == tag then
            return "duplicate"
        end

        if cand.revision > ctl.revision and not cand.record and cand.state == "empty"
           and ctl.absent and ctl.gate == GATE_READY
        then
            -- still no record, just at a later revision: only move the
            -- watermark, nothing that a reader can see has changed
            ctl.revision = cand.revision
            local ok, err = store_ctl(dict, ctl)
            if not ok then
                return nil, "failed to update the control record: " .. err
            end

            return "watermark"
        end
    end

    if ctl.seq >= MAX_SEQ then
        return nil, "sequence exhausted"
    end

    local epoch = dict:get(EPOCH_KEY)
    local seq = ctl.seq + 1
    local snapshot, enc_err = encode_snapshot(epoch, seq, cand, published_at)
    if not snapshot then
        return nil, "failed to encode the snapshot: " .. enc_err
    end

    -- close the gate for the new target first: whatever happens next, no
    -- reader can keep using the previous snapshot as the current one
    ctl.gate = GATE_PENDING
    ctl.absent = not cand.record
    ctl.seq = seq
    ctl.revision = cand.revision
    ctl.generation = generation
    ctl.err = ERR_NONE
    ctl.tag = tag
    local ok, err = store_ctl(dict, ctl)
    if not ok then
        return nil, "failed to update the control record: " .. err
    end

    ok, err = dict:safe_set(SNAP_KEY, snapshot)
    if not ok then
        ctl.gate = GATE_UNAVAILABLE
        ctl.err = ERR_SNAPSHOT
        store_ctl(dict, ctl)
        return nil, "failed to store the snapshot: " .. err
    end

    ctl.gate = GATE_READY
    ok, err = store_ctl(dict, ctl)
    if not ok then
        return nil, "failed to update the control record: " .. err
    end

    return "published"
end


--- Publish a candidate.
--
-- The candidate is a complete target, parsed, decrypted and validated by the
-- producer beforehand:
--
--  * `state`: "ready" (non-empty `keys`), "empty" (no record, an empty array
--    or a disabled record) or "unavailable" (the record cannot be loaded).
--  * `revision`: revision of the record (etcd modifiedIndex, configuration
--    version in standalone). Without a record, the latest revision the
--    producer has observed, which is never reported as a source version.
--  * `record`: whether a record exists; `source` and `disabled` describe it.
--  * `keys`: ordered array of 80-byte keys, for "ready" only.
--  * `error`: reason of "unavailable"; it must not contain key material.
--  * `generation`: config generation of the producer, nil when unknown.
--
-- A candidate older than the watermark is ignored, so is a repeated one
-- unless the previous attempt failed: retrying the same revision after a local
-- failure produces a new version. The same revision with a different content
-- (the record read with another local policy or keyring after a reload) is
-- published as a new version too. A candidate of a newer config generation
-- always publishes, one of an older generation never does.
--
-- Must run in a context where it may sleep briefly (e.g. a timer).
--
-- @treturn string|nil "published", "duplicate", "stale" or "watermark"
-- @treturn string|nil the error
function _M.publish(cand)
    local ok, err = check_candidate(cand)
    if not ok then
        return nil, err
    end

    return with_lock(do_publish, cand, now())
end


local function do_enter_generation(dict, generation)
    local ctl = decode_ctl(dict:get(CTL_KEY))
    if not ctl then
        return nil, "invalid control record"
    end

    if generation <= ctl.generation then
        return false
    end

    if ctl.seq >= MAX_SEQ then
        return nil, "sequence exhausted"
    end

    ctl.gate = GATE_PENDING
    ctl.seq = ctl.seq + 1
    ctl.generation = generation
    ctl.err = ERR_GENERATION
    ctl.tag = EMPTY_TAG
    local ok, err = store_ctl(dict, ctl)
    if not ok then
        return nil, "failed to update the control record: " .. err
    end

    return true
end


--- Switch the state to a newer config generation.
--
-- The first process of a new config generation closes the gate until a
-- producer of that generation publishes, and from then on the producers of
-- older generations cannot write back. Later calls for the same generation
-- are no-ops, so the switch happens once.
--
-- @tparam number generation the config generation of the caller
-- @treturn boolean|nil true if the switch happened, false if not needed
-- @treturn string|nil the error
function _M.enter_generation(generation)
    if not is_uint(generation, MAX_GENERATION) then
        return nil, "invalid generation"
    end

    return with_lock(do_enter_generation, generation)
end


local function ctl_view(ctl, epoch)
    return {
        version = (epoch or "") .. ":" .. ctl.seq,
        seq = ctl.seq,
        gate = gate_names[ctl.gate],
        revision = ctl.revision,
        generation = ctl.generation,
        error = err_msgs[ctl.err],
    }
end


--- Read the control record only.
--
-- Cheap enough for a hot path: a consumer compares `version` with what it has
-- applied and reads the snapshot only when they differ.
--
-- @treturn table|nil version, seq, gate ("none", "pending", "unavailable" or
-- "ready"), revision, generation and error
-- @treturn string|nil the error
function _M.read_control()
    local dict = get_dict()
    if not dict then
        return nil, "shared dict '" .. _M.DICT_NAME .. "' not found"
    end

    local ctl = decode_ctl(dict:get(CTL_KEY))
    if not ctl then
        return nil, "control record unavailable"
    end

    return ctl_view(ctl, dict:get(EPOCH_KEY))
end


local function decode_snapshot(raw)
    local snap = core.json.decode(raw)
    if type(snap) ~= "table" or not state_names[snap.state] or type(snap.keys) ~= "table" then
        return nil
    end

    for i, key in ipairs(snap.keys) do
        key = type(key) == "string" and decode_base64(key)
        if not key or #key ~= _M.KEY_SIZE then
            return nil
        end
        snap.keys[i] = key
    end

    if type(snap.origin) == "table" then
        snap.origin.revision = tonumber(snap.origin.revision)
    end

    return snap
end


--- Read the current target consistently.
--
-- The control record is read before and after the snapshot; when they differ
-- or do not match, the read is retried a bounded number of times. Only a
-- `gate` of "ready" carries a snapshot; any other gate means that no shared
-- key may be used, and "pending" is never a final target.
--
-- @treturn table|nil version, seq, gate, state ("ready", "empty",
-- "unavailable" or "pending"), keys (raw), updated_at, origin (source,
-- disabled, revision; nil without a record) and error
-- @treturn string|nil the error, e.g. "inconsistent"
function _M.read()
    local dict = get_dict()
    if not dict then
        return nil, "shared dict '" .. _M.DICT_NAME .. "' not found"
    end

    for _ = 1, READ_ATTEMPTS do
        local raw_ctl = dict:get(CTL_KEY)
        local ctl = decode_ctl(raw_ctl)
        if not ctl then
            return nil, "control record unavailable"
        end

        local epoch = dict:get(EPOCH_KEY)
        local view = ctl_view(ctl, epoch)
        if ctl.gate ~= GATE_READY then
            view.state = ctl.gate == GATE_UNAVAILABLE and "unavailable" or "pending"
            view.keys = {}
            return view
        end

        local raw_snap = dict:get(SNAP_KEY)
        if raw_snap and dict:get(CTL_KEY) == raw_ctl then
            local snap = decode_snapshot(raw_snap)
            if snap and snap.seq == ctl.seq and snap.epoch == epoch then
                view.state = snap.state
                view.keys = snap.keys
                view.updated_at = snap.updated_at
                view.origin = snap.origin
                view.error = snap.error
                return view
            end
        end
    end

    return nil, "inconsistent"
end


local function worker_key(subsystem, lane, slot)
    return "w:" .. subsystem .. ":" .. lane .. ":" .. slot
end


local function check_identity(identity)
    if type(identity) ~= "table" then
        return nil, "invalid identity"
    end

    if identity.subsystem ~= "http" and identity.subsystem ~= "stream" then
        return nil, "invalid subsystem"
    end

    if not is_uint(identity.slot, _M.MAX_WORKER_SLOTS - 1) then
        return nil, "invalid slot"
    end

    if not is_uint(identity.pid, MAX_GENERATION) then
        return nil, "invalid pid"
    end

    if identity.generation ~= nil and not is_uint(identity.generation, MAX_GENERATION) then
        return nil, "invalid generation"
    end

    return true
end


local function note_worker_failure(dict, code)
    -- both are pre-created numbers, updated in place
    dict:safe_set(WFAIL_AT_KEY, now())
    dict:safe_set(WFAIL_CODE_KEY, code)
end


local function encode_worker_record(identity, record)
    if type(record) ~= "table" then
        return nil, "invalid record"
    end

    local contexts = record.contexts or {}
    if type(contexts) ~= "table" or #contexts > _M.MAX_CONTEXTS then
        return nil, "too many contexts"
    end

    local ctxs = core.table.new(#contexts, 0)
    for i, c in ipairs(contexts) do
        if type(c) ~= "table" then
            return nil, "invalid context"
        end

        ctxs[i] = {
            id = c.id,
            ok = c.ok and true or false,
            error = truncate(c.error, _M.MAX_CONTEXT_ERROR_LEN),
        }
    end

    local s = core.json.encode({
        subsystem = identity.subsystem,
        slot = identity.slot,
        pid = identity.pid,
        generation = identity.generation or 0,
        target_version = record.target_version,
        applied_version = record.applied_version,
        contexts = setmetatable(ctxs, core.json.array_mt),
        applied_at = record.applied_at,
        seen_at = now(),
        error = truncate(record.error),
    })

    if #s > _M.WORKER_RECORD_SIZE then
        return nil, "record too large"
    end

    -- padded to a fixed size, so that refreshing a record never allocates
    return s .. str_rep(" ", _M.WORKER_RECORD_SIZE - #s)
end


local function do_put_worker_record(dict, identity, record)
    local value, err = encode_worker_record(identity, record)
    if not value then
        note_worker_failure(dict, WFAIL_INVALID)
        return nil, err
    end

    local lane = (identity.generation or 0) % _M.WORKER_LANES
    local key = worker_key(identity.subsystem, lane, identity.slot)

    local old = dict:get(key)
    if old then
        old = core.json.decode(old)
        if type(old) == "table" and old.pid ~= identity.pid
           and type(old.seen_at) == "number" and now() - old.seen_at < _M.WORKER_LIVE_TTL
        then
            -- the slot is held by another live process, e.g. a third
            -- overlapping generation: never take over its record
            note_worker_failure(dict, WFAIL_SLOT_BUSY)
            return nil, "worker record slot is in use"
        end
    end

    local ok, set_err = dict:safe_set(key, value)
    if not ok then
        note_worker_failure(dict, WFAIL_NO_MEMORY)
        return nil, "failed to store the worker record: " .. set_err
    end

    local wmax = dict:get(WMAX_KEY) or 0
    if identity.slot + 1 > wmax then
        dict:safe_set(WMAX_KEY, identity.slot + 1)
    end

    return true
end


--- Write the record of a consumer process.
--
-- `identity` is `{subsystem = "http"|"stream", slot = n, pid = n,
-- generation = n}` where the slot and the generation come from the process
-- identity API of the runtime (the slot of a worker is its worker id, the
-- privileged agent has the last one). Records are bounded: one per subsystem,
-- slot and lane, a lane holding a config generation (the current one and one
-- draining), MAX_CONTEXTS contexts and MAX_ERROR_LEN bytes of error each.
--
-- `record` holds `target_version`, `applied_version`, `contexts` (array of
-- `{id = n, ok = bool, error = string}`), `applied_at` and `error`.
--
-- A failure never evicts anything; it is remembered so that the Control API
-- reports it, and the process has no record, so it never counts as applied.
--
-- @treturn boolean|nil true on success
-- @treturn string|nil the error
function _M.put_worker_record(identity, record)
    local ok, err = check_identity(identity)
    if not ok then
        return nil, err
    end

    return with_lock(do_put_worker_record, identity, record)
end


local function do_delete_worker_record(dict, identity)
    local lane = (identity.generation or 0) % _M.WORKER_LANES
    local key = worker_key(identity.subsystem, lane, identity.slot)

    local old = dict:get(key)
    if not old then
        return false
    end

    old = core.json.decode(old)
    if type(old) == "table" and old.pid == identity.pid
       and old.generation == (identity.generation or 0)
    then
        dict:delete(key)
        return true
    end

    -- the slot already belongs to another process
    return false
end


--- Delete the record of a consumer process, only if it still owns the slot.
--
-- @treturn boolean|nil true if deleted
-- @treturn string|nil the error
function _M.delete_worker_record(identity)
    local ok, err = check_identity(identity)
    if not ok then
        return nil, err
    end

    return with_lock(do_delete_worker_record, identity)
end


--- Read all the consumer records, with a bounded number of gets.
--
-- @treturn table|nil array of records
-- @treturn string|nil the error
function _M.worker_records()
    local dict = get_dict()
    if not dict then
        return nil, "shared dict '" .. _M.DICT_NAME .. "' not found"
    end

    local records = {}
    local wmax = dict:get(WMAX_KEY) or 0
    if wmax > _M.MAX_WORKER_SLOTS then
        wmax = _M.MAX_WORKER_SLOTS
    end

    for _, subsystem in ipairs(_M.SUBSYSTEMS) do
        for lane = 0, _M.WORKER_LANES - 1 do
            for slot = 0, wmax - 1 do
                local raw = dict:get(worker_key(subsystem, lane, slot))
                if raw then
                    local rec = core.json.decode(raw)
                    if type(rec) == "table" then
                        core.table.insert(records, rec)
                    end
                end
            end
        end
    end

    return records
end


--- Called in init_worker of both subsystems.
--
-- Pre-creates the control records if the init phase could not, then lets the
-- first process of a new config generation switch the state to it.
function _M.init_worker()
    if not get_dict() then
        core.log.info("shared dict '", _M.DICT_NAME, "' not found, ",
                      "TLS session ticket keys are not available without APISIX Runtime")
        return
    end

    local ok, err = _M.init()
    if not ok then
        core.log.error("failed to initialize the TLS session ticket state: ", err)
        return
    end

    local generation = _M.process_generation()
    if not generation then
        return
    end

    -- with_lock may sleep, which init_worker does not allow
    ngx.timer.at(0, function(premature)
        if premature then
            return
        end

        local _, enter_err = _M.enter_generation(generation)
        if enter_err then
            core.log.error("failed to switch the TLS session ticket state to config ",
                           "generation ", generation, ": ", enter_err)
        end
    end)
end


--- The latest failure to store a consumer record, if it is recent.
--
-- @treturn string|nil the reason
-- @treturn number|nil when it happened
function _M.worker_record_failure()
    local dict = get_dict()
    if not dict then
        return nil
    end

    local at = dict:get(WFAIL_AT_KEY)
    if not at or at == 0 or now() - at >= _M.WORKER_LIVE_TTL then
        return nil
    end

    return wfail_msgs[dict:get(WFAIL_CODE_KEY)] or "failed to store the worker record", at
end


return _M
