local redis_new     = require("resty.redis").new
local core          = require("apisix.core")
local assert        = assert
local math          = require "math"
local floor         = math.floor

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

function _M.new(plugin_name, conf, max, burst, default_conn_delay)

    local self = {
        conf = conf,
        plugin_name = plugin_name,
        burst = burst,
        max = max + 0,    -- just to ensure the param is good
        unit_delay = default_conn_delay,
    }
    return setmetatable(self, mt)
end


function _M.incoming(self, key, commit)
    local max = self.max

    -- init redis
    local conf = self.conf
    local red, err = redis_cli(conf)
    if not red then
        return red, err
    end

    self.committed = false

    prefix = conf.redis_prefix
    local hash_key = prefix .. ":connection_hash"

    local conn, err
    if commit then
        conn, err = red:hincrby(hash_key, key, 1)
        if not conn then
            return nil, err
        end

        if conn > max + self.burst then
            conn, err = red:hincrby(hash_key, key, -1)
            if not conn then
                return nil, err
            end
            return nil, "rejected"
        end
        self.committed = true

    else
        conn_from_red, err = red:hget(hash_key, key)
        if err then
            return nil, err
        end
        conn = (conn_from_red or 0) + 1
    end

    core.log.error("", "redis-conn-limit: ", conn, "connection limit reached")
    if conn > max then
        -- make the excessive connections wait
        return self.unit_delay * floor((conn - 1) / max), conn
    end

    -- we return a 0 delay by default
    return 0, conn
end


function _M.is_committed(self)
    return self.committed
end


local function leaving_thread(premature, self, key, req_latency)

    -- init redis
    local conf = self.conf
    local red, err = redis_cli(conf)
    if not red then
        return red, err
    end

    prefix = conf.redis_prefix
    local hash_key = prefix .. ":connection_hash"

    local conn, err = red:hincrby(hash_key, key, -1)
    if not conn then
        return nil, err
    end

    if req_latency then
        local unit_delay = self.unit_delay
        self.unit_delay = (req_latency + unit_delay) / 2
    end

    return conn
end


function _M.leaving(self, key, req_latency)
    assert(key)

    -- log_by_lua can't use cosocket
    local ok, err = ngx.timer.at(0, leaving_thread, self, key, req_latency)
    if not ok then
        core.log.error("failed to create timer: ", err)
        return nil, err
    end

    return ok

end



return _M
