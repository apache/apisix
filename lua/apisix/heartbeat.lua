-- Copyright (C) Yuansheng Wang


local json = require("apisix.core.json")
local version = require("apisix.core.version")
local log = require("apisix.core.log")
local timer = require("apisix.core.timer")
local http = require("resty.http")


local apisix_heartbeat_addr = "https://iresty.com/apisix/heartbeat"
local _M = {version = 0.1}


local function request_apisix_svr(body)
    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    http_cli:set_timeout(60 * 1000)

    local res
    res, err = http_cli:request_uri(apisix_heartbeat_addr, {
        method = "POST",
        body = body,
        ssl_verify = false,
        keepalive = false,
    })

    if err then
        return nil, err
    end

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    return res
end


local function report()
    -- ngx.sleep(3)
    local info = {
        version = version,
    }

    local body, err = json.encode(info)
    if not body then
        log.error("failed to encode hearbeat information: ", err)
        return
    end

    local res
    res, err = request_apisix_svr(body)
    if not res then
        log.error("failed to report heartbeat information: ", err)
    else
        log.info("succed to report body: ", json.encode(res, true))
    end
end


function _M.init_worker()
    local ok, err = timer.new({name = "heartbeat", callback_fun = report})
    if not ok then
        log.error("failed to create timer: ", err)
    else
        log.warn("succed to create timer: heartbeat")
    end
end


return _M
