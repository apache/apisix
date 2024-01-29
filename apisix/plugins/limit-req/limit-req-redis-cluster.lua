local rediscluster      = require("resty.rediscluster")
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

local _M = {version = 0.1}


local mt = {
    __index = _M
}


local function new_redis_cluster(conf)
    local config = {
        name = conf.redis_cluster_name,
        serv_list = {},
        read_timeout = conf.redis_timeout,
        auth = conf.redis_password,
        dict_name = "plugin-limit-req-redis-cluster-slot-lock",
        connect_opts = {
            ssl = conf.redis_cluster_ssl,
            ssl_verify = conf.redis_cluster_ssl_verify,
        }
    }

    for i, conf_item in ipairs(conf.redis_cluster_nodes) do
        local host, port, err = core.utils.parse_addr(conf_item)
        if err then
            return nil, "failed to parse address: " .. conf_item
                        .. " err: " .. err
        end

        config.serv_list[i] = {ip = host, port = port}
    end

    local red_cli, err = rediscluster:new(config)
    if not red_cli then
        return nil, "failed to new redis cluster: " .. err
    end

    return red_cli
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

-- the "commit" argument controls whether should we record the event in shm.
function _M.incoming(self, key, commit)
    local rate = self.rate
    local now = ngx_now() * 1000
    local conf = self.conf

    local excess

    -- init redis
    local red, err = new_redis_cluster(conf)
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
