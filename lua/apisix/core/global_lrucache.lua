-- Copyright (C) Yuansheng Wang

local lru_new = require("resty.lrucache").new
local lru_items = lru_new(200)  -- todo: support to config in yaml.


local _M = {version = 0.1}


function _M.fetch(name, count, version)
    local cache = lru_items:get(name)
    if cache and cache.version == version then
        return cache
    end

    cache = lru_new(count)
    cache.version = version
    lru_items:set(name, cache)
    return cache
end


function _M.set(self, name, lru)
    return lru_items:set(name, lru)
end


function _M.delete(name)
    return lru_items:delete(name)
end


return _M
