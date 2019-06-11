-- Copyright (C) Yuansheng Wang

local config_etcd = require("apisix.core.config_etcd").new()
local apisix_version = require("apisix.core.version")
local apisix_id = require("apisix.core.id")
local timer = require("apisix.core.timer")
local json = require("apisix.core.json")
local log = require("apisix.core.log")
local http = require("resty.http")
local encode_args = ngx.encode_args


local apisix_heartbeat_addr = "https://iresty.com/apisix/heartbeat?"
local _M = {version = 0.1}


local function request_apisix_svr(args)
    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    http_cli:set_timeout(60 * 1000)

    local res
    res, err = http_cli:request_uri(apisix_heartbeat_addr .. args, {
        method = "GET",
        ssl_verify = false,
        keepalive = false,
        headers = {
            ["User-Agent"] = "curl",
        }
    })

    if err then
        return nil, err
    end

    if res.status ~= 200 then
        return nil, "invalid response code: " .. res.status
    end

    return res
end


local function report()
    -- ngx.sleep(3)
    local etcd_version, err = config_etcd:server_version()
    if not etcd_version then
        log.error("failed to fetch etcd version: ", err)
    end

    local info = {
        version = apisix_version,
        plugins = config_etcd.local_conf().plugins,
        etcd_version = etcd_version,
        uuid = apisix_id.get(),
    }

    local args, err = encode_args(info)
    if not args then
        log.error("failed to encode hearbeat information: ", err)
        return
    end
    log.debug("heartbeat body: ", args)

    local res
    res, err = request_apisix_svr(args)
    if not res then
        log.error("failed to report heartbeat information: ", err)
    else
        log.info("succed to report body: ", json.delay_encode(res, true))
    end
end


function _M.init_worker()
    local local_conf = config_etcd.local_conf()
    if local_conf.apisix and not local_conf.apisix.enable_heartbeat then
        log.info("disabled the heartbeat feature")
        return
    end

    local res, err = timer.new("heartbeat", report,
                               {check_interval = 60 * 60})
    if not res then
        log.error("failed to create timer: ", err)
    else
        log.info("succed to create timer: heartbeat")
    end
end


return _M
