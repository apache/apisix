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


local _M = {
    version = 0.1,
    priority = 1000,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


local ngx_status = {}
local ngx_statu_items = {
    "active", "accepted", "handled", "total",
    "reading", "writing", "waiting"
}


local function collect()
    core.log.info("try to collect node status from etcd: ",
                  "/node_status/" .. apisix_id)
    local res, err = core.etcd.get("/node_status/" .. apisix_id)
    if not res then
        return 500, {error = err}
    end

    return res.status, res.body
end


local function run_loop()
    local res, err = core.http.request_self("/apisix/nginx_status", {
                                                keepalive = false,
                                            })
    if not res then
        if err then
            return core.log.error("failed to fetch nginx status: ", err)
        end
        return
    end

    if res.status ~= 200 then
        core.log.error("failed to fetch nginx status, response code: ",
                       res.status)
        return
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        core.log.error("failed to re.gmatch Nginx status: ", err)
        return
    end

    core.table.clear(ngx_status)
    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        ngx_status[name] = val[0]
    end

    local res, err = core.etcd.set("/node_status/" .. apisix_id, ngx_status)
    if not res then
        core.log.error("failed to create etcd client: ", err)
        return
    end

    if res.status >= 300 then
        core.log.error("failed to update node status, code: ", res.status,
                       " body: ", core.json.encode(res.body, true))
        return
    end
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


    local timer
function _M.init()
    if timer or ngx.worker.id() ~= 0 then
        return
    end
    timer = core.timer.new(plugin_name, run_loop, {check_interval = 5 * 60})
end


return _M
