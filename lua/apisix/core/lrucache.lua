local lru_new = require("resty.lrucache").new
-- todo: support to config it in YAML.
local GLOBAL_TTL = 60 * 60          -- 60 min
local GLOBAL_ITEMS_COUNT = 1024
local PLUGIN_TTL = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT = 512
local global_lrus = lru_new(GLOBAL_ITEMS_COUNT)


local _M = {version = 0.1}


local function _global_lrus(key, version, create_obj_fun, ...)
    local lru, stale_lru = global_lrus:get(key)
    if lru and lru._version == version then
        return lru
    end

    if stale_lru and stale_lru._version == version then
        global_lrus:set(key, lru, GLOBAL_TTL)
        return stale_lru
    end

    lru = create_obj_fun(...)
    lru._version = version
    global_lrus:set(key, lru, GLOBAL_TTL)
    return lru
end
_M.global = _global_lrus


local function _plugin(plugin_name, key, version, create_obj_fun, ...)
    -- todo: support to config in yaml.
    local lru_global = _global_lrus("/plugin/" .. plugin_name, nil,
                                    lru_new, PLUGIN_ITEMS_COUNT)

    local lru, stale_lru = lru_global:get(key)
    if lru and lru._version == version then
        return lru
    end

    if stale_lru and stale_lru._version == version then
        lru_global:set(key, stale_lru, PLUGIN_TTL)
        return stale_lru
    end

    lru = create_obj_fun(...)
    lru._version = version
    lru_global:set(key, lru, PLUGIN_TTL)

    return lru
end
_M.plugin = _plugin


function _M.plugin_ctx(plugin_name, api_ctx, create_obj_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id

    return _plugin(plugin_name, key, api_ctx.conf_version, create_obj_fun, ...)
end


return _M
