local lru_new = require("resty.lrucache").new
local global_lrus = lru_new(256)  -- todo: support to config in yaml.

local _M = {version = 0.1}


local function _global_lrus(name, count)
    local lru = global_lrus:get(name)
    if lru then
        return lru
    end

    lru = lru_new(count)
    global_lrus:set(name, lru)
    return lru
end
_M.global = _global_lrus


local function _plugin_key(plugin_name, key, version, callback_fun, ...)
    local lru_plugin_conf = _global_lrus("/plugin/" .. plugin_name, 32)

    -- todo: support `stale` object
    local obj = lru_plugin_conf:get(key)
    if not obj or obj.version ~= version then
        obj = callback_fun(...)
        obj.version = version
        lru_plugin_conf:set(key, obj)
    end

    return obj
end
_M.plugin = _plugin_key


function _M.plugin_ctx(plugin_name, api_ctx, callback_fun, ...)
    local key = api_ctx.conf_type .. "#" .. api_ctx.conf_id

    return _plugin_key(plugin_name, key, api_ctx.conf_version,
                       callback_fun, ...)
end


return _M
