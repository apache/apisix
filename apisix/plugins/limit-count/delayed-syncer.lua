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
local resty_lock = require "resty.lock"
local cjson_safe = require "cjson.safe"
local table_new = require("table.new")
local table_nkeys = require("table.nkeys")

local setmetatable = setmetatable
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local tab_insert = table.insert
local type = type
local pcall = pcall

local ngx_now = ngx.now
local ngx_shared = ngx.shared
local worker_id = ngx.worker.id
local ngx_worker = ngx.worker
local ngx_sleep = ngx.sleep
local ngx_timer = ngx.timer


local KEY_PREFIX_LOCKER = "locker#"
local KEY_PREFIX_LOCAL_DELTA = "local_delta#" -- delta since last time sync with redis
local KEY_PREFIX_LOCAL_DELTA_KEYS = "local_delta_keys#" -- keys to be sync with redis next time
 -- per plugin instance timer, in server instance dimension
local KEY_PREFIX_SYNC_TIMER = "sync_timer#"
local KEY_PREFIX_REMOTE_QUOTA = "remote_quota#" -- save remaining/reset/sync_at in JSON format

-- Maximum number of keys allowed in the delayed-sync queue per syncer instance.
-- Each request does one unconditional lpush, so without this cap the queue can fill
-- the fixed-size `plugin-limit-count` shared dict under high request rates.
-- Each entry is a rate-limit key string; 10000 entries is well within typical usage.
local MAX_DELAYED_SYNC_QUEUE_SIZE = 10000

-- Throttle for the queue-saturation warning: at most one log per worker per
-- syncer per this many seconds. A saturated queue happens under sustained high
-- request rate, so logging every request would flood the error log.
local QUEUE_FULL_WARN_INTERVAL = 10
local last_queue_full_warn = {}

local time_to_sync_records = {}

local _M = {}

local mt = {
    __index = _M
}


function _M.build_key(self, prefix, key)
    if self.shd_per_worker then
        return prefix .. worker_id() .. "#" .. key
    end
    return prefix .. key
end


function _M.key_locker(self, key)
    return self:build_key(KEY_PREFIX_LOCKER, key)
end


function _M.key_local_delta(self, key)
    return self:build_key(KEY_PREFIX_LOCAL_DELTA, key)
end


function _M.key_local_delta_keys(self, syncer_id)
    return self:build_key(KEY_PREFIX_LOCAL_DELTA_KEYS, syncer_id)
end


function _M.key_sync_timer(self, syncer_id)
    return self:build_key(KEY_PREFIX_SYNC_TIMER, syncer_id)
end


function _M.key_remote_quota(self, key)
    return self:build_key(KEY_PREFIX_REMOTE_QUOTA, key)
end


function _M.sync_to_shm(self, key, remaining, reset, local_delta)
    local quota = {
        remaining = remaining,
        reset = reset,
        sync_at = ngx_now(),
    }

    local _, err, quota_json

    quota_json, err = cjson_safe.encode(quota)
    if err then
        core.log.error("encode remote_quota to json failed: ", err)
        return err
    end

    _, err = self.shd:set(self:key_remote_quota(key), quota_json, 2 * self.window)
    if err then
        core.log.error("set remote quota to shm failed: ", err, ", key: ", key)
        return err
    end

    _, err = self.shd:incr(self:key_local_delta(key), -local_delta, 0, 2 * self.window)
    if err then
        core.log.error("incr local delta shm to failed: ", err, ", key: ", key)
        return err
    end
end


function _M.release(self, syncer_id)
    self.shd:delete(self:key_sync_timer(syncer_id))
end


function _M.delayed_sync(self, key, cost, syncer_id)
    local locker, err = resty_lock:new(self.lock_shdict_name)
    if not locker then
        core.log.error("new resty locker failed: ", err, ", syncer_id: ", syncer_id)
        return nil, nil, err
    end

    local elapsed
    elapsed, err = locker:lock(self:key_locker(key))
    if err then
        core.log.error("lock key(" .. key .. ") failed: ", err, ", elapsed: ", elapsed)
        return nil, nil, err
    end

    -- wrap the delayed syncer call in a pcall to avoid the lock being held forever
    local ok, remaining, reset, err = pcall(self._delayed_sync, self, key, cost, syncer_id)
    if not ok then
        err = remaining
        remaining = nil
        core.log.error("delayed sync failed: ", err, ", key: ", key)
    end

    local ok, err_unlock = locker:unlock()
    if not ok then
        core.log.error("unlock key(" .. key .. ") failed: ", err_unlock)
    end

    return remaining, reset, err
end


function _M._delayed_sync(self, key, cost, syncer_id)
    local _, reset, remote_quota_json
    local local_delta, err  = self.shd:get(self:key_local_delta(key))
    if err then
        return nil, nil, err
    end
    if not local_delta then
        local_delta = 0
    end

    remote_quota_json, err = self.shd:get(self:key_remote_quota(key))
    if err then
        return nil, nil, err
    end

    core.log.info("trying to delayed sync, key: ", key,
        ", local_delta: ", local_delta,
        ", cost: ", cost,
        ", syncer_id: ", syncer_id)

    local remote_remaining, remote_reset, sync_at, quota
    if remote_quota_json then
        core.log.info("remote_quota_json: ", remote_quota_json)
        quota, err = cjson_safe.decode(tostring(remote_quota_json))
        if err then
            core.log.error("decode remote_quota_json failed: ", err)
            return nil, nil, err
        end

        remote_remaining, remote_reset, sync_at = quota.remaining, quota.reset, quota.sync_at
        reset = remote_reset - (ngx_now() - sync_at)
        if reset < 0 then
            reset = 0 -- flag that indicates needing to sync with redis
            time_to_sync_records[syncer_id] = nil
        end
    end

    if not remote_quota_json or 0 == reset then
        remote_remaining = 0
        remote_reset = 0
        local remaining_or_err
        -- prefer commit() when the limiter provides one (sliding window), so an
        -- already-permitted delta is always written even if the remote counter
        -- is at/over the limit; the fixed-window backend has no commit() and its
        -- incoming() already increments before reporting "rejected".
        local flush = self.limiter.commit or self.limiter.incoming
        _, remaining_or_err, reset = flush(self.limiter, key, local_delta)
        if type(remaining_or_err) ~= "string" then
            remote_remaining = remaining_or_err
            remote_reset = reset
        elseif remaining_or_err ~= "rejected" then
            core.log.error("sync to redis failed: ", remaining_or_err, ", key: ", key)
            if self.limiter.fallback_limiter then
                core.log.warn("try use fallback limiter to do rate limiting")
                _, remaining_or_err, reset =
                       self.limiter.fallback_limiter:incoming(key, local_delta)
                if type(remaining_or_err) ~= "string" then
                    remote_remaining = remaining_or_err
                    remote_reset = reset
                elseif remaining_or_err ~= "rejected" then
                    core.log.error("sync to fallback_limiter failed: ",
                                        remaining_or_err, ", key: ", key)
                else
                    remote_remaining = 0
                    remote_reset = reset
                end
            else
                return nil, nil, remaining_or_err
            end
        else
            -- rejected: rate limit exceeded on Redis
            remote_remaining = 0
            remote_reset = reset
        end

        core.log.info("sync to shm, key: ", key, ", remote_remaining: ", remote_remaining,
                    ", remote_reset: ", remote_reset)
        err = self:sync_to_shm(key, remote_remaining, remote_reset, local_delta)
        if err then
            return nil, nil, err
        end
    end

    local queue_key = self:key_local_delta_keys(syncer_id)
    local queue_len, q_err = self.shd:llen(queue_key)
    if q_err then
        core.log.warn("failed to get delayed-sync queue length: ", q_err)
    end
    local enqueued = false
    if not (queue_len and queue_len >= MAX_DELAYED_SYNC_QUEUE_SIZE) then
        _, err = self.shd:lpush(queue_key, key)
        if not err then
            enqueued = true
        end
    end

    -- The queue is saturated, either the cap is reached, or lpush failed because a
    -- concurrent worker filled the shm between the llen check and the lpush. Either
    -- way, skip the enqueue and let the request proceed on the already-computed
    -- remaining quota; the delta stays in the per-key shm slot and syncs once the
    -- queue drains. Returning an error here would 500 requests under the same load
    -- the cap is meant to survive, so we degrade instead.
    if not enqueued then
        local now = ngx_now()
        local last = last_queue_full_warn[syncer_id]
        if not last or now - last >= QUEUE_FULL_WARN_INTERVAL then
            last_queue_full_warn[syncer_id] = now
            core.log.warn("delayed-sync queue saturated, skipping enqueue; syncer_id: ",
                          syncer_id, ", queue_len: ", queue_len or "unknown",
                          ", err: ", err or "queue full")
        end
    end

    local key_sync_timer = self:key_sync_timer(syncer_id)

    -- timer has not started or has already triggered, try starting a new one
    local now = ngx_now()
    if not time_to_sync_records[syncer_id] or time_to_sync_records[syncer_id] <= now then
        local time_to_sync = now + self.sync_interval
        -- nginx server instance dimension, each plug-in instance corresponds to a timer
        -- shd:add - ensure only one worker can start timer
        local success
        success, err = self.shd:add(key_sync_timer, time_to_sync)
        if success then
            -- start timer ASAP
            local ok, err = ngx_timer.at(
                0,
                function (premature)
                    if not premature then
                        local ok, err = pcall(self.sync, self, syncer_id, time_to_sync)
                        if not ok then
                            core.log.error("sync failed: ", err, ", syncer_id: ", syncer_id)
                        end
                    end
                    self:release(syncer_id)
                end
            )
            if not ok then
                local running = ngx_timer.running_count()
                local pending = ngx_timer.pending_count()
                core.log.error("failed to create timer: ", err, ", running_count: ", running,
                ", pending_count: ", pending, ", syncer_id: ", syncer_id)
                self:release(syncer_id)
            else
                time_to_sync_records[syncer_id] = time_to_sync
            end
        elseif err == "exists" then
            -- other workers
            time_to_sync_records[syncer_id], err = self.shd:get(key_sync_timer)
            if err then
                core.log.error("get sync timer created time failed: ", err)
            end
        else
            core.log.error("try starting new timer failed: ", err)
            return nil, nil, err
        end
    end

    local remaining = remote_remaining - local_delta - cost
    if 0 <= remaining then
        _, err = self.shd:incr(self:key_local_delta(key), cost, 0, 2 * self.window)
        if err then
            core.log.error("incr local delta to shm failed: ", err, ", key: ", key)
            return nil, nil, err
        end
    end

    return remaining, reset
end


local function sync_key(self, key)
    local delta, err = self.shd:get(self:key_local_delta(key))
    if err then
        core.log.error("get local delta from shm failed: ", err)
    end

    if delta then
        local flush = self.limiter.commit or self.limiter.incoming
        local _, remaining_or_err, reset = flush(self.limiter, key, delta)
        -- compat
        if type(remaining_or_err) ~= "string" then
            self:sync_to_shm(key, remaining_or_err, reset, delta)
        elseif remaining_or_err ~= "rejected" then
            core.log.error("sync to redis failed: ", remaining_or_err, ", key: ", key)
            if self.limiter.fallback_limiter then
                core.log.warn("try use fallback limiter to do rate limiting")
                if delta < 1 then
                    delta = 1
                end
                _, remaining_or_err, reset =
                   self.limiter.fallback_limiter:incoming(key, delta)
                if type(remaining_or_err) ~= "string" then
                    self:sync_to_shm(key, remaining_or_err, reset, delta)
                elseif remaining_or_err ~= "rejected" then
                    core.log.error("sync to fallback_limiter failed: ",
                                        remaining_or_err, ", key: ", key)
                else
                    self:sync_to_shm(key, 0, reset, delta)
                end
            end
        else
            self:sync_to_shm(key, 0, reset, delta)
        end
    end
end


function _M.sync(self, syncer_id, time_to_sync)
    local key_local_delta_keys = self:key_local_delta_keys(syncer_id) -- name of keys queue
    local local_delta_keys_dedup = {} -- duplicate removal
    while not ngx_worker.exiting() and time_to_sync > ngx_now() do
        local key, err = self.shd:rpop(key_local_delta_keys)
        if err then
            core.log.error("shdict.rpop failed: ", err, ", syncer_id: ", syncer_id)
            return
        end
        if key then
            if not local_delta_keys_dedup[key] then
                local_delta_keys_dedup[key] = true
            end
        else
            ngx_sleep(0.001)
        end
    end

    if ngx_worker.exiting() then
        core.log.info("sync interrupted due to worker exit")
        return
    end

    -- drain all remaining keys from the queue
    local key = {}
    while key ~= nil do
        local err
        key, err = self.shd:rpop(key_local_delta_keys)
        if err then
            core.log.error("shdict.rpop failed: ", err, ", syncer_id: ", syncer_id)
            return
        end

        if key then
            if not local_delta_keys_dedup[key] then
                local_delta_keys_dedup[key] = true
            end
        end
    end

    local nkeys = table_nkeys(local_delta_keys_dedup)
    local local_delta_keys_uniq = table_new(nkeys, 0)

    core.log.info(nkeys, " keys to be sync, time_to_sync: ", time_to_sync)

    for key, _ in pairs(local_delta_keys_dedup) do
        tab_insert(local_delta_keys_uniq, key)
    end

    local locker, err = resty_lock:new(self.lock_shdict_name)
    if not locker then
        core.log.error("new resty locker failed: ", err, ", syncer_id: ", syncer_id)
        return
    end

    local elapsed
    for _, key in ipairs(local_delta_keys_uniq) do
        elapsed, err = locker:lock(self:key_locker(key))
        if err then
            core.log.error("lock key(" .. key .. ") failed: ", err, ", elapsed: ", elapsed)
            return
        end

        local ok, err = pcall(sync_key, self, key)
        if not ok then
            core.log.error("sync failed: ", err, ", key: ", key)
        end

        local ok, err_unlock = locker:unlock()
        if not ok then
            core.log.error("unlock key(" .. key .. ") failed: ", err_unlock)
        end
    end
end


function _M.new(shdict_name, limit, window, conf, limiter)
    local shd = ngx_shared[shdict_name]
    if not shd then
        return nil, "shared dict (" .. shdict_name .. ") not found"
    end
    local lock_shdict_name = shdict_name .. "-lock"
    local self = {
        shdict_name = shdict_name,
        lock_shdict_name = lock_shdict_name,
        shd = shd,
        conf = conf,
        limit = limit,
        window = window,
        limiter = limiter,
        sync_interval = conf.sync_interval,
    }
    -- self.shd_per_worker = true: simulate multiple nginx server instance
    if conf._shd_per_worker then
        self.shd_per_worker = true
    end
    return setmetatable(self, mt)
end


return _M
