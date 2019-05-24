-- Copyright (C) Yuansheng Wang
-- only support to cache lua table object

local lru_new = require("resty.lrucache").new
-- todo: support to config it in YAML.
local GLOBAL_TTL = 60 * 60          -- 60 min
local GLOBAL_ITEMS_COUNT = 1024
local PLUGIN_TTL = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 8
local global_lrus = lru_new(GLOBAL_ITEMS_COUNT)


-- here is a hack way
local plugins_conf = {
    ["balancer"] = {
        count = 512,
        ttl = 10 * 60,
    }
}


local _M = {version = 0.1}


local function global_lru(key, version, create_obj_fun, ...)
    local obj, stale_obj = global_lrus:get(key)
    if obj and obj._cache_ver == version then
        return obj
    end

    if stale_obj and stale_obj._cache_ver == version then
        global_lrus:set(key, obj, GLOBAL_TTL)
        return stale_obj
    end

    obj = create_obj_fun(...)
    obj._cache_ver = version
    global_lrus:set(key, obj, GLOBAL_TTL)
    return obj
end
_M.global = global_lru


local function _plugin(plugin_name, key, version, create_obj_fun, ...)
    local conf = plugins_conf[plugin_name]
    local lru_global = global_lru("/plugin/" .. plugin_name, nil,
            lru_new, conf and conf.count or PLUGIN_ITEMS_COUNT)

    local obj, stale_obj = lru_global:get(key)
    if obj and obj._cache_ver == version then
        return obj
    end

    if stale_obj and stale_obj._cache_ver == version then
        lru_global:set(key, stale_obj, conf and conf.ttl or PLUGIN_TTL)
        return stale_obj
    end

    obj = create_obj_fun(...)
    obj._cache_ver = version
    lru_global:set(key, obj, PLUGIN_TTL)

    return obj
end
_M.plugin = _plugin


function _M.plugin_ctx(plugin_name, api_ctx, create_obj_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id
    return _plugin(plugin_name, key, api_ctx.conf_version, create_obj_fun, ...)
end


return _M
