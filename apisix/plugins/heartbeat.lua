--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local http = require("resty.http")
local encode_args = ngx.encode_args
local plugin_name = "heartbeat"
local ngx = ngx


local apisix_heartbeat_addr = "https://www.iresty.com/apisix/heartbeat?"


local schema = {
    type = "object",
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 100,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


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
    local etcd_version, etcd_version_err
    local local_conf = core.config.local_conf()

    if local_conf.apisix.config_center == "etcd" then
        etcd_version, etcd_version_err = core.etcd.server_version()
        if not etcd_version then
            core.log.error("failed to fetch etcd version: ", etcd_version_err)
        else
            etcd_version = etcd_version.body and etcd_version.body.etcdserver
        end
    end

    core.log.info(core.json.encode(etcd_version))

    local info = {
        version = core.version,
        plugins = local_conf.plugins,
        config_center = local_conf.apisix.config_center,
        etcd_version = etcd_version,
        etcd_version_err = etcd_version_err,
        uuid = core.id.get(),
    }

    -- core.log.info(core.json.delay_encode(info, true))
    local args, err = encode_args(info)
    if not args then
        core.log.error("failed to encode hearbeat information: ", err)
        return
    end
    core.log.info("heartbeat body: ", args)

    local res
    res, err = request_apisix_svr(args)
    if not res then
        core.log.info("failed to report heartbeat information: ", err)
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
