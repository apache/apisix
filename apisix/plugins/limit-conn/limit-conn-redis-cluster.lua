local rediscluster      = require("resty.rediscluster")
local core              = require("apisix.core")
local assert            = assert
local setmetatable      = setmetatable
local math              = require "math"
local floor             = math.floor
local ipairs            = ipairs

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
        dict_name = conf.dict_name,
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
    local red, err = new_redis_cluster(conf)
    if not red then
        return red, err
    end

    self.committed = false

    prefix = conf.redis_prefix
    key = prefix .. ":" .. key

    local conn, err
    if commit then
        conn, err = red:incrby(key, 1)
        if not conn then
            return nil, err
        end

        if conn > max + self.burst then
            conn, err = red:incrby(key, -1)
            if not conn then
                return nil, err
            end
            return nil, "rejected"
        end
        self.committed = true

    else
        conn_from_red, err = red:get(key)
        if err then
            return nil, err
        end
        conn = (conn_from_red or 0) + 1
    end

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
    local red, err = new_redis_cluster(conf)
    if not red then
        return red, err
    end

    prefix = conf.redis_prefix
    key = prefix .. ":" .. key

    local conn, err = red:incrby(key, -1)
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
