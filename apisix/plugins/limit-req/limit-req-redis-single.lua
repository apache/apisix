local redis_new     = require("resty.redis").new
local core              = require("apisix.core")
local assert            = assert
local setmetatable      = setmetatable
local math              = require "math"
local abs               = math.abs
local floor             = math.floor
local max               = math.max
local ipairs            = ipairs
local ngx_now           = ngx.now
local ngx_null          = ngx.null

local setmetatable  = setmetatable


local _M = {version = 0.1}


local mt = {
    __index = _M
}


local function redis_cli(conf)
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- default 1sec

    red:set_timeouts(timeout, timeout, timeout)

    local sock_opts = {
        ssl = conf.redis_ssl,
        ssl_verify = conf.redis_ssl_verify
    }

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379, sock_opts)
    if not ok then
        core.log.error(" redis connect error, error: ", err)
        return false, err
    end

    local count
    count, err = red:get_reused_times()
    if 0 == count then
        if conf.redis_password and conf.redis_password ~= '' then
            local ok, err
            if conf.redis_username then
                ok, err = red:auth(conf.redis_username, conf.redis_password)
            else
                ok, err = red:auth(conf.redis_password)
            end
            if not ok then
                return nil, err
            end
        end

        -- select db
        if conf.redis_database ~= 0 then
            local ok, err = red:select(conf.redis_database)
            if not ok then
                return false, "failed to change redis db, err: " .. err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end
    return red, nil
end

function _M.new(plugin_name, conf, rate, burst)
    local self = {
        conf = conf,
        plugin_name = plugin_name,
        burst = burst * 1000,
        rate = rate * 1000,
    }
    return setmetatable(self, mt)
end


function _M.incoming(self, key, commit)
    local rate = self.rate
    local now = ngx_now() * 1000
    local conf = self.conf

    local excess

    -- init redis
    local red, err = redis_cli(conf)
    if not red then
        return red, err
    end

    local prefix = conf.redis_prefix
    key = prefix .. ":" .. key

    local excess, err = red:hget(key, "excess")
    if err then
        return nil, err
    end
    local last, err = red:hget(key, "last")
    if err then
        return nil, err
    end
    core.log.error("excess: ", excess)
    core.log.error("last: ", last)
    if excess ~= ngx_null and last ~= ngx_null then
        excess = tonumber(excess)
        last = tonumber(last)
        local elapsed = now - last
        excess = max(excess - rate * abs(elapsed) / 1000 + 1000, 0)

        if excess > self.burst then
            return nil, "rejected"
        end
    else
        excess = 0
    end

    if commit then
        local ok
        local err
        ok, err = red:hset(key, "excess", excess)
        if not ok then
            return nil, err
        end

        ok, err = red:hset(key, "last", now)
        if not ok then
            return nil, err
        end
    end

    -- return the delay in seconds, as well as excess
    return excess / rate, excess / 1000
end



return _M
