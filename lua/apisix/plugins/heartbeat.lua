-- Copyright (C) Yuansheng Wang

local core = require("apisix.core")
local http = require("resty.http")
local encode_args = ngx.encode_args
local plugin_name = "heartbeat"
local ngx = ngx


local apisix_heartbeat_addr = "https://www.iresty.com/apisix/heartbeat?"


local _M = {
    version = 0.1,
    priority = 100,
    name = plugin_name,
}


local function request_apisix_svr(args)
    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    http_cli:set_timeout(5 * 1000)

    local res
    res, err = http_cli:request_uri(apisix_heartbeat_addr .. args, {
        method = "GET",
        ssl_verify = false,
        keepalive = false,
        headers = {
            ["User-Agent"] = "curl/7.54.0",
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
    local etcd_version, err = core.etcd.server_version()
    if not etcd_version then
        core.log.error("failed to fetch etcd version: ", err)
    end

    local info = {
        version = core.version,
        plugins = core.config.local_conf().plugins,
        etcd_version = etcd_version.body,
        uuid = core.id.get(),
    }

    -- core.log.info(core.json.delay_encode(info, true))
    local args, err = encode_args(info)
    if not args then
        core.log.error("failed to encode hearbeat information: ", err)
        return
    end
    core.log.debug("heartbeat body: ", args)

    local res
    res, err = request_apisix_svr(args)
    if not res then
        core.log.error("failed to report heartbeat information: ", err)
        return
    end

    core.log.info("succeed to report body: ",
                  core.json.delay_encode(res, true))
end

do
    local timer

function _M.init()
    if timer or ngx.worker.id() ~= 0 then
        return
    end

    local err
    timer, err = core.timer.new("heartbeat", report, {check_interval = 60 * 60})
    if not timer then
        core.log.error("failed to create timer: ", err)
    else
        core.log.info("succeed to create timer: heartbeat")
    end
end

end -- do


return _M
