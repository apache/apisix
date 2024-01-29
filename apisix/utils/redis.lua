local redis_new     = require("resty.redis").new
local core          = require("apisix.core")


local _M = {version = 0.1}

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



function _M.new(conf)
    return redis_cli(conf)
end

return _M
