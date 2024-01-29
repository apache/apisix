local rediscluster      = require("resty.rediscluster")
local core              = require("apisix.core")
local ipairs            = ipairs

local _M = {version = 0.1}

local function new_redis_cluster(conf)
    local config = {
        name = conf.redis_cluster_name,
        serv_list = {},
        read_timeout = conf.redis_timeout,
        auth = conf.redis_password,
        dict_name = "plugin-limit-conn-redis-cluster-slot-lock",
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


function _M.new(conf)
     return new_redis_cluster(conf)
end


return _M
