local limit_local_new = require("resty.limit.count").new
local ngx_time = ngx.time

local _M = {}

local mt = {
    __index = _M
}

function _M.set_endtime(self,key,time_window)
    -- set an end time
    local end_time = ngx_time() + time_window
    -- save to dict by key
    self.dict:set(key, end_time, time_window)

    local reset = time_window
    return reset
end

function _M.read_reset(self, key)
    -- read from dict
    local end_time = (self.dict:get(key) or 0)
    local reset = end_time - ngx_time()
    if reset < 0 then
        reset = 0
    end
    return reset
end

function _M.new(plugin_name, limit, window, conf)
    assert(limit > 0 and window > 0)

    local self = {
        limit_count = limit_local_new(plugin_name, limit, window, conf),
        dict = ngx.shared["plugin-limit-count-reset-header"]
    }

    return setmetatable(self, mt)
end

function _M.incoming(self, key, commit)
    return self.limit_count:incoming(key, commit)
end

return _M
