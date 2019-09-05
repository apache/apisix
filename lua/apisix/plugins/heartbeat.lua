--[[
    心跳，报告当前apisix节点信息的
    需要修改上报目标地址，才能用
--]]
local core = require("apisix.core")
local http = require("resty.http")
local encode_args = ngx.encode_args
local plugin_name = "heartbeat"
local ngx = ngx

-- 上报中心，需要调整成总部中心
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

    --上报信息
    local info = {
        version = core.version,       --版本号
        plugins = core.config.local_conf().plugins, --当前节点的启动插件
        etcd_version = etcd_version.body,   --etcd链接信息
        uuid = core.id.get(),    --当前节点的唯一标志id
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
