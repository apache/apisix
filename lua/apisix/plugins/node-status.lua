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
local ngx = ngx
local re_gmatch = ngx.re.gmatch
local plugin_name = "node-status"
local apisix_id = core.id.get()
local ipairs = ipairs
local local_conf = core.config.local_conf()

local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
}

local ngx_status = {}
local ngx_statu_items = {
    "active", "accepted", "handled", "total",
    "reading", "writing", "waiting"
}


local function collect_node_info()
    local res, err = core.http.request_self("/apisix/nginx_status", {
                                                keepalive = false,
                                            })
    if not res then
        return nil, "failed to fetch nginx status: " .. err
    end

    if res.status ~= 200 then
        return nil, "failed to fetch nginx status, got http status: " .. res.status
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        return nil, "failed to re.gmatch Nginx status: " .. err
    end

    core.table.clear(ngx_status)
    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        ngx_status[name] = val[0]
    end

    local node_info = {
        id = apisix_id,
        apisix_version = core.version.VERSION,
        nginx_version = ngx.config.nginx_version,
        plugins = local_conf.plugins,
        config_center = local_conf.apisix.config_center,
        status = ngx_status,
    }

    local data, err = core.json.encode(node_info)
    if not data then
        core.log.error("failed to encode node information: ", err)
        return nil, "failed to encode node information: " .. err
    end

    return data, nil
end

local function report()
    local data, err = collect_node_info()
    if not data then
        core.log.error("failed to report node information:", err)
    end

    local key = "/cluster/" .. apisix_id
    local res, err = core.etcd.set(key, data, 10)
    if not res then
        core.log.error("failed to report node information[", key, "]: ", err)
    end
end

local function collect()
    local data, err = collect_node_info()
    if not data then
        core.log.error("failed to report node information:", err)
        return 500, err
    end

    return 200, data
end

function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/status",
            handler = collect,
        }
    }
end


do
    local timer

function _M.init()
    if timer or ngx.worker.id() ~= 0 then
        return
    end

    local err
    timer, err = core.timer.new("cluster", report, {check_interval = 5})
    if not timer then
        core.log.error("failed to create timer: ", err)
    else
        core.log.info("succeed to create timer: cluster")
    end
end

end -- do

return _M
