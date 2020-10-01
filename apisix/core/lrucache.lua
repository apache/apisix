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

local lru_new = require("resty.lrucache").new
local resty_lock = require("resty.lock")
local tostring = tostring
local ngx = ngx
local get_phase = ngx.get_phase


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

local GLOBAL_ITEMS_COUNT = 1024
local GLOBAL_TTL         = 60 * 60          -- 60 min
local PLUGIN_TTL         = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 8
local global_lru_fun


local function fetch_valid_cache(lru_obj, invalid_stale, item_ttl,
                                 item_release, key, version)
    local obj, stale_obj = lru_obj:get(key)
    if obj and obj.ver == version then
        return obj
    end

    if not invalid_stale and stale_obj and stale_obj.ver == version then
        lru_obj:set(key, stale_obj, item_ttl)
        return stale_obj
    end

    if item_release and obj then
        item_release(obj.val)
    end

    return nil
end


local function new_lru_fun(opts)
    local item_count = opts and opts.count or GLOBAL_ITEMS_COUNT
    local item_ttl = opts and opts.ttl or GLOBAL_TTL
    local item_release = opts and opts.release
    local invalid_stale = opts and opts.invalid_stale
    local lru_obj = lru_new(item_count)

    return function (key, version, create_obj_fun, ...)
        if not can_yield_phases[get_phase()] then
            local cache_obj = fetch_valid_cache(lru_obj, invalid_stale,
                                item_ttl, item_release, key, version)
            if cache_obj then
                return cache_obj.val
            end

            local obj, err = create_obj_fun(...)
            if obj ~= nil then
                lru_obj:set(key, {val = obj, ver = version}, item_ttl)
            end

            return obj, err
        end

        local cache_obj = fetch_valid_cache(lru_obj, invalid_stale, item_ttl,
                            item_release, key, version)
        if cache_obj then
            return cache_obj.val
        end

        local lock, err = resty_lock:new(lock_shdict_name)
        if not lock then
            return nil, "failed to create lock: " .. err
        end

        local key_s = tostring(key)
        local elapsed, err = lock:lock(key_s)
        if not elapsed then
            return nil, "failed to acquire the lock: " .. err
        end

        cache_obj = fetch_valid_cache(lru_obj, invalid_stale, item_ttl,
                        nil, key, version)
        if cache_obj then
            lock:unlock()
            return cache_obj.val
        end

        local obj, err = create_obj_fun(...)
        if obj ~= nil then
            lru_obj:set(key, {val = obj, ver = version}, item_ttl)
        end
        lock:unlock()

        return obj, err
    end
end


global_lru_fun = new_lru_fun()


local function _plugin(plugin_name, key, version, create_obj_fun, ...)
    local lru_global = global_lru_fun("/plugin/" .. plugin_name, nil,
                                      lru_new, PLUGIN_ITEMS_COUNT)

    local obj, stale_obj = lru_global:get(key)
    if obj and obj.ver == version then
        return obj.val
    end

    if stale_obj and stale_obj.ver == version then
        lru_global:set(key, stale_obj, PLUGIN_TTL)
        return stale_obj
    end

    local err
    obj, err = create_obj_fun(...)
    if obj ~= nil then
        lru_global:set(key, {val = obj, ver = version}, PLUGIN_TTL)
    end

    return obj, err
end


local _M = {
    version = 0.1,
    new = new_lru_fun,
    global = global_lru_fun,
    plugin = _plugin,
}


function _M.plugin_ctx(plugin_name, api_ctx, create_obj_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id
    return _plugin(plugin_name, key, api_ctx.conf_version, create_obj_fun, ...)
end


return _M
