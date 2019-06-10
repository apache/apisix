-- Copyright (C) Yuansheng Wang
-- only support to cache lua table object

local lru_new = require("resty.lrucache").new
-- todo: support to config it in YAML.
local GLOBAL_TTL = 60 * 60          -- 60 min
local GLOBAL_ITEMS_COUNT = 1024
local PLUGIN_TTL = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 8
local global_lrus = lru_new(GLOBAL_ITEMS_COUNT)
local log = require("apisix.core.log")


local _M = {version = 0.1}
local mt = { __index = _M }


local function global_lru(key, version, create_obj_fun, ...)
    local obj, stale_obj = global_lrus:get(key)
    if obj and obj._cache_ver == version then
        return obj
    end

    if stale_obj and stale_obj._cache_ver == version then
        global_lrus:set(key, obj, GLOBAL_TTL)
        return stale_obj
    end

    local err
    obj, err = create_obj_fun(...)
    if type(obj) == 'table' then
        obj._cache_ver = version
        global_lrus:set(key, obj, GLOBAL_TTL)
    else
        log.error('failed to call create_obj_fun in global_lru(), only support to cache Lua table object.')
    end

    return obj, err
end
_M.global = global_lru


local function _plugin(count, ttl, plugin_name, key, version, create_obj_fun,
                       ...)
    local lru_global = global_lru("/plugin/" .. plugin_name, nil,
            lru_new, count)

    local obj, stale_obj = lru_global:get(key)
    if obj and obj._cache_ver == version then
        return obj
    end

    if stale_obj and stale_obj._cache_ver == version then
        lru_global:set(key, stale_obj, ttl)
        return stale_obj
    end

    local err
    obj, err = create_obj_fun(...)
    if type(obj) == 'table' then
        obj._cache_ver = version
        lru_global:set(key, obj, ttl)
    else
        log.error('failed to call create_obj_fun in _plugin(), only support to cache Lua table object.')
    end

    return obj, err
end


function _M.plugin(plugin_name, key, version, create_obj_fun, ...)
    return _plugin(PLUGIN_ITEMS_COUNT, PLUGIN_TTL, plugin_name, key,
                   version, create_obj_fun, ...)
end


function _M.plugin_ctx(plugin_name, api_ctx, create_obj_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id
    return _plugin(PLUGIN_ITEMS_COUNT, PLUGIN_TTL, plugin_name, key,
                   api_ctx.conf_version, create_obj_fun, ...)
end


function _M.new(opts)
    local item_count = opts and opts.count or GLOBAL_ITEMS_COUNT
    local item_ttl = opts and opts.ttl or GLOBAL_TTL

    local lru_obj = lru_new(item_count)

    return function (key, version, create_obj_fun, ...)
        local obj, stale_obj = lru_obj:get(key)
        if obj and obj._cache_ver == version then
            return obj
        end

        if stale_obj and stale_obj._cache_ver == version then
            lru_obj:set(key, obj, item_ttl)
            return stale_obj
        end

        local err
        obj, err = create_obj_fun(...)
        if type(obj) == 'table' then
            obj._cache_ver = version
            lru_obj:set(key, obj, item_ttl)
        else
            log.warn('only support to cache Lua table object with lrucache')
        end

        return obj, err
    end
end


return _M
