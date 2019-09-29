local redis_new = require("resty.redis").new
local core = require("apisix.core")


local _M = {}


local mt = {
    __index = _M
}


function _M.new(limit, window, redis_conf)
    assert(limit > 0 and window > 0)

    local self = {limit = limit, window = window, redis = redis_conf}
    return setmetatable(self, mt)
end


function _M.incoming(self, key)
    local red = redis_new()
    local conf = self.redis
    local timeout = conf.timeout or 1000    -- 1sec
    core.log.info("ttl key: ", key, " timeout: ", timeout)

    red:set_timeouts(timeout, timeout, timeout)

    local ok, err = red:connect(conf.host, conf.port or 6379)
    if not ok then
        return false, err
    end

    local limit = self.limit
    local window = self.window
    local remaining

    local ret, err = red:ttl(key)
    core.log.info("ttl key: ", key, " ret: ", ret, " err: ", err)
    if ret < 0 then
        ret, err = red:set(key, limit -1, "EX", window, "NX")
        if not ret then
            return nil, err
        end

        return true, limit -1
    end

    remaining, err = red:incrby(key, -1)
    if not remaining then
        return nil, err
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err
    end

    if remaining < 0 then
        return nil, "rejected"
    end

    return 0, remaining
end


return _M
