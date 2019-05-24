-- Copyright (C) Yuansheng Wang
-- only support to cache lua table object

local lru_new = require("resty.lrucache").new
-- todo: support to config it in YAML.
local GLOBAL_TTL = 60 * 60          -- 60 min
local GLOBAL_ITEMS_COUNT = 1024
local PLUGIN_TTL = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 8
local global_lrus = lru_new(GLOBAL_ITEMS_COUNT)


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

    obj = create_obj_fun(...)
    obj._cache_ver = version
    global_lrus:set(key, obj, GLOBAL_TTL)
    return obj
end
_M.global = global_lru


local function _plugin(count, ttl, plugin_name, key, version, create_obj_fun, ...)
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

    obj = create_obj_fun(...)
    obj._cache_ver = version
    lru_global:set(key, obj, ttl)

    return obj
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


local function _obj_plugin_ctx(self, plugin_name, api_ctx, create_obj_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id
    return _plugin(self.plugin_count, self.plugin_ttl, plugin_name, key,
                   api_ctx.conf_version, create_obj_fun, ...)
end


local function _obj_plugin(self, plugin_name, key, version, create_obj_fun, ...)
    return _plugin(self.plugin_count, self.plugin_ttl, plugin_name, key,
                   version, create_obj_fun, ...)
end


function _M.new(opts)
    local plugin_count = opts and opts.plugin_count or PLUGIN_ITEMS_COUNT
    local plugin_ttl = opts and opts.plugin_ttl or PLUGIN_TTL

    return setmetatable({
        plugin_count = plugin_count,
        plugin_ttl = plugin_ttl,
        plugin_ctx = _obj_plugin_ctx,
        plugin = _obj_plugin,
    }, mt)
end


return _M
