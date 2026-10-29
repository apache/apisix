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

--- LRU Caching Implementation.
--
-- @module core.lrucache

local lru_new = require("resty.lrucache").new
local resty_lock = require("resty.lock")
local log = require("apisix.core.log")
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local unpack = unpack
local tostring = tostring
local setmetatable = setmetatable
local ngx = ngx
local get_phase = ngx.get_phase
local ngx_now = ngx.now
local timer_every = ngx.timer.every
local exiting = ngx.worker.exiting


local lock_shdict_name = "lrucache-lock"
if ngx.config.subsystem == "stream" then
    lock_shdict_name = lock_shdict_name .. "-" .. ngx.config.subsystem
end


local can_yield_phases = {
    ssl_session_fetch = true,
    ssl_session_store = true,
    rewrite = true,
    access = true,
    content = true,
    timer = true
}

-- weak keys: an lrucache dropped by its owner (e.g. rebuilt with a new ttl)
-- must not be kept alive by its pending refresh entries
local stale_obj_pool = setmetatable({}, {__mode = "k"})

-- lru_obj -> {inactive = seconds, access_times = {key -> last access time}}
-- for the lrucaches created with `inactive`; weak keys for the same reason
local inactive_lru_pool = setmetatable({}, {__mode = "k"})

local GLOBAL_ITEMS_COUNT = 1024
local GLOBAL_TTL         = 60 * 60          -- 60 min
local PLUGIN_TTL         = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 8
local global_lru_fun


local function fetch_valid_cache(lru_obj, invalid_stale, refresh_stale, item_ttl,
                                 key, version, create_obj_fun, ...)
    local obj, stale_obj = lru_obj:get(key)
    if obj and obj.ver == version then
        return obj
    end

    if stale_obj and stale_obj.ver == version then
        if not invalid_stale then
            lru_obj:set(key, stale_obj, item_ttl)
            return stale_obj
        end

        if refresh_stale then
            -- update a pending refresh in place: refresh_stale_objs writes
            -- back only while the pending entry is still the one it ran
            local pending = stale_obj_pool[lru_obj][key]
            if pending then
                pending.fn = create_obj_fun
                pending.args = {...}
                pending.ver = version
                pending.ttl = item_ttl
            else
                stale_obj_pool[lru_obj][key] = {
                    fn = create_obj_fun,
                    args = {...},
                    ver = version,
                    ttl = item_ttl,
                }
            end
            return stale_obj
        end
    end

    return nil
end


local function new_lru_fun(opts)
    local item_count, item_ttl
    if opts and opts.type == 'plugin' then
        item_count = opts.count or PLUGIN_ITEMS_COUNT
        item_ttl = opts.ttl or PLUGIN_TTL
    else
        item_count = opts and opts.count or GLOBAL_ITEMS_COUNT
        item_ttl = opts and opts.ttl or GLOBAL_TTL
    end

    local invalid_stale = opts and opts.invalid_stale
    local refresh_stale = opts and opts.refresh_stale
    local serial_creating = opts and opts.serial_creating
    local lru_obj = lru_new(item_count)

    local neg_lru_obj
    if opts and opts.neg_ttl and opts.neg_count then
        neg_lru_obj = lru_new(opts.neg_count)
    end

    stale_obj_pool[lru_obj] = {}

    -- `inactive`: drop an item not accessed for this many seconds, so an
    -- expired item nobody asks for anymore is not kept until count eviction
    local access_times
    if opts and opts.inactive then
        access_times = {}
        inactive_lru_pool[lru_obj] = {
            inactive = opts.inactive,
            access_times = access_times,
        }
    end

    return function (key, version, create_obj_fun, ...)
        -- check negative cache first
        if neg_lru_obj then
            local neg_obj = neg_lru_obj:get(key)
            if neg_obj and neg_obj.ver == version then
                return nil, neg_obj.err
            end
        end

        if not serial_creating or not can_yield_phases[get_phase()] then
            local cache_obj = fetch_valid_cache(lru_obj, invalid_stale, refresh_stale,
                                item_ttl, key, version, create_obj_fun, ...)
            if cache_obj then
                if access_times then
                    access_times[key] = ngx_now()
                end
                return cache_obj.val
            end

            local obj, err = create_obj_fun(...)
            if obj ~= nil then
                lru_obj:set(key, {val = obj, ver = version}, item_ttl)
                if access_times then
                    access_times[key] = ngx_now()
                end
            elseif neg_lru_obj then
                -- cache the failure in negative cache
                neg_lru_obj:set(key, {err = err, ver = version}, opts.neg_ttl)
            end

            return obj, err
        end

        local cache_obj = fetch_valid_cache(lru_obj, invalid_stale, refresh_stale, item_ttl,
                            key, version, create_obj_fun, ...)
        if cache_obj then
            if access_times then
                access_times[key] = ngx_now()
            end
            return cache_obj.val
        end

        local lock, err = resty_lock:new(lock_shdict_name)
        if not lock then
            return nil, "failed to create lock: " .. err
        end

        local key_s = tostring(key)
        log.info("try to lock with key ", key_s)

        local elapsed, err = lock:lock(key_s)
        if not elapsed then
            return nil, "failed to acquire the lock: " .. err
        end

        cache_obj = fetch_valid_cache(lru_obj, invalid_stale, refresh_stale, item_ttl,
                        key, version, create_obj_fun, ...)
        if cache_obj then
            lock:unlock()
            log.info("unlock with key ", key_s)
            if access_times then
                access_times[key] = ngx_now()
            end
            return cache_obj.val
        end

        local obj, err = create_obj_fun(...)
        if obj ~= nil then
            lru_obj:set(key, {val = obj, ver = version}, item_ttl)
            if access_times then
                access_times[key] = ngx_now()
            end
        elseif neg_lru_obj then
            -- cache the failure in negative cache
            neg_lru_obj:set(key, {err = err, ver = version}, opts.neg_ttl)
        end
        lock:unlock()
        log.info("unlock with key ", key_s)

        return obj, err
    end
end


global_lru_fun = new_lru_fun()


local function plugin_ctx_key_and_ver(api_ctx, extra_key)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id

    if extra_key then
        key = key .. "#" .. extra_key
    end

    return key, api_ctx.conf_version
end

---
--  Cache some objects for plugins to avoid duplicate resources creation.
--
-- @function core.lrucache.plugin_ctx
-- @tparam table lrucache LRUCache object instance.
-- @tparam table api_ctx The request context.
-- @tparam string extra_key Additional parameters for generating the lrucache identification key.
-- @tparam function create_obj_func Functions for creating cache objects.
-- If the object does not exist in the lrucache, this function is
-- called to create it and cache it in the lrucache.
-- @treturn table The object cached in lrucache.
-- @usage
-- local function create_obj() {
-- --   create the object
-- --   return the object
-- }
-- local obj, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_obj)
-- -- obj is the object cached in lrucache
local function plugin_ctx(lrucache, api_ctx, extra_key, create_obj_func, ...)
    local key, ver = plugin_ctx_key_and_ver(api_ctx, extra_key)
    return lrucache(key, ver, create_obj_func, ...)
end

local function plugin_ctx_id(api_ctx, extra_key)
    local key, ver = plugin_ctx_key_and_ver(api_ctx, extra_key)
    return key .. "#" .. ver
end


local function refresh_stale_objs()
    -- snapshot first: creating an object may yield, and the pool can change
    -- meanwhile (new stale hits, purge_inactive_objs)
    local pending = {}
    for lru_obj, keys in pairs(stale_obj_pool) do
        for key, new_obj in pairs(keys) do
            pending[#pending + 1] = {lru_obj, keys, key, new_obj}
        end
    end

    for _, item in ipairs(pending) do
        local lru_obj, keys, key, new_obj = item[1], item[2], item[3], item[4]
        if keys[key] ~= new_obj then
            goto continue
        end

        local ver, ttl = new_obj.ver, new_obj.ttl
        local obj, err = new_obj.fn(unpack(new_obj.args))
        if obj ~= nil then
            -- the item may have been purged while refreshing; writing it back
            -- then would resurrect it without an access record
            if keys[key] == new_obj then
                lru_obj:set(key, {val = obj, ver = ver}, ttl)
                keys[key] = nil
                log.info("successfully refresh stale obj for key ",
                            tostring(key), " to ver ", ver)
            end
        else
            log.error("failed to refresh stale obj for key ", key, ": ", err)
        end

        ::continue::
    end
end


local function purge_inactive_objs()
    local now = ngx_now()
    for lru_obj, inactive_lru in pairs(inactive_lru_pool) do
        local access_times = inactive_lru.access_times
        local inactive = inactive_lru.inactive
        local pending = stale_obj_pool[lru_obj]
        for key, access_time in pairs(access_times) do
            if now - access_time > inactive then
                lru_obj:delete(key)
                access_times[key] = nil
                if pending then
                    pending[key] = nil
                end
            end
        end
    end
end


local function run_every_second(name, fn)
    local running = false
    timer_every(1, function ()
        if not exiting() then
            if running then
                log.info(name, " is already running, skipping this iteration")
                return
            end
            running = true
            local ok, err = pcall(fn)
            if not ok then
                log.error("failed to run ", name, ": ", err)
            end
            running = false
        end
    end)
end


local function init_worker()
    run_every_second("timer_refresh_stale", refresh_stale_objs)
    -- a separate timer, so a slow refresh does not hold up purging
    run_every_second("timer_purge_inactive", purge_inactive_objs)
end


local _M = {
    version = 0.1,
    init_worker = init_worker,
    new = new_lru_fun,
    global = global_lru_fun,
    plugin_ctx = plugin_ctx,
    plugin_ctx_id = plugin_ctx_id,
}


return _M
