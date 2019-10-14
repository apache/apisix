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
local setmetatable = setmetatable
local getmetatable = getmetatable
local type = type

-- todo: support to config it in YAML.
local GLOBAL_ITEMS_COUNT= 1024
local GLOBAL_TTL        = 60 * 60          -- 60 min
local PLUGIN_TTL        = 5 * 60           -- 5 min
local PLUGIN_ITEMS_COUNT= 8
local global_lru_fun
local lua_metatab = {}


local function new_lru_fun(opts)
    local item_count = opts and opts.count or GLOBAL_ITEMS_COUNT
    local item_ttl = opts and opts.ttl or GLOBAL_TTL
    local item_release = opts and opts.release
    local lru_obj = lru_new(item_count)

    return function (key, version, create_obj_fun, ...)
        local obj, stale_obj = lru_obj:get(key)
        if obj and obj._cache_ver == version then
            local met_tab = getmetatable(obj)
            if met_tab ~= lua_metatab then
                return obj
            end

            return obj.val
        end

        if stale_obj and stale_obj._cache_ver == version then
            lru_obj:set(key, stale_obj, item_ttl)

            local met_tab = getmetatable(stale_obj)
            if met_tab ~= lua_metatab then
                return stale_obj
            end

            return stale_obj.val
        end

        if item_release and obj then
            item_release(obj)
        end

        local err
        obj, err = create_obj_fun(...)
        if type(obj) == 'table' then
            obj._cache_ver = version
            lru_obj:set(key, obj, item_ttl)

        elseif obj ~= nil then
            local cached_obj = setmetatable({val = obj, _cache_ver = version},
                                            lua_metatab)
            lru_obj:set(key, cached_obj, item_ttl)
        end

        return obj, err
    end
end


global_lru_fun = new_lru_fun()


local function _plugin(plugin_name, key, version, create_obj_fun, ...)
    local lru_global = global_lru_fun("/plugin/" .. plugin_name, nil,
                                      lru_new, PLUGIN_ITEMS_COUNT)

    local obj, stale_obj = lru_global:get(key)
    if obj and obj._cache_ver == version then
        local met_tab = getmetatable(obj)
        if met_tab ~= lua_metatab then
            return obj
        end

        return obj.val
    end

    if stale_obj and stale_obj._cache_ver == version then
        lru_global:set(key, stale_obj, PLUGIN_TTL)
        return stale_obj
    end

    local err
    obj, err = create_obj_fun(...)
    if type(obj) == 'table' then
        obj._cache_ver = version
        lru_global:set(key, obj, PLUGIN_TTL)

    elseif obj ~= nil then
        local cached_obj = setmetatable({val = obj, _cache_ver = version},
                                        lua_metatab)
        lru_global:set(key, cached_obj, PLUGIN_TTL)
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
