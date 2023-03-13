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
local require = require
local core = require("apisix.core")
local timers = require("apisix.timers")
local common = require("apisix.plugins.server-info.common")

local ngx_time = ngx.time
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id
local type = type

local default_report_ttl = 60
local lease_id

local attr_schema = {
    type = "object",
    properties = {
        report_ttl = {
            type = "integer",
            description = "live time for server info in etcd",
            default = default_report_ttl,
            minimum = 3,
            maximum = 86400,
        }
    }
}

local _M = {}


local function set(key, value, ttl)
    local res_new, err = core.etcd.set(key, value, ttl)
    if not res_new then
        core.log.error("failed to set server_info: ", err)
        return nil, err
    end

    if not res_new.body.lease_id then
        core.log.error("failed to get lease_id: ", err)
        return nil, err
    end

    lease_id = res_new.body.lease_id

    -- set or update lease_id
    local ok, err = common.internal_status:set("lease_id", lease_id)
    if not ok then
        core.log.error("failed to set lease_id to shdict: ", err)
        return nil, err
    end

    return true
end


local function report(premature, report_ttl)
    if premature then
        return
    end

    -- get apisix node info
    local server_info, err = common.get()
    if not server_info then
        core.log.error("failed to get server_info: ", err)
        return
    end

    if server_info.etcd_version == "unknown" then
        local res, err = core.etcd.server_version()
        if not res then
            core.log.error("failed to fetch etcd version: ", err)
            return

        elseif type(res.body) ~= "table" then
            core.log.error("failed to fetch etcd version: bad version info")
            return

        else
            if res.body.etcdcluster == "" then
                server_info.etcd_version = res.body.etcdserver
            else
                server_info.etcd_version = res.body.etcdcluster
            end
        end
    end

    -- get inside etcd data, if not exist, create it
    local key = "/data_plane/server_info/" .. server_info.id
    local res, err = core.etcd.get(key)
    if not res or (res.status ~= 200 and res.status ~= 404) then
        core.log.error("failed to get server_info from etcd: ", err)
        return
    end

    if not res.body.node then
        local ok, err = set(key, server_info, report_ttl)
        if not ok then
            core.log.error("failed to set server_info to etcd: ", err)
            return
        end

        return
    end

    local ok = core.table.deep_eq(server_info, res.body.node.value)
    -- not equal, update it
    if not ok then
        local ok, err = set(key, server_info, report_ttl)
        if not ok then
            core.log.error("failed to set server_info to etcd: ", err)
            return
        end

        return
    end

    -- get lease_id from ngx dict
    lease_id, err = common.internal_status:get("lease_id")
    if not lease_id then
        core.log.error("failed to get lease_id from shdict: ", err)
        return
    end

    -- call keepalive
    local res, err = core.etcd.keepalive(lease_id)
    if not res then
        core.log.error("send heartbeat failed: ", err)
        return
    end

    local data, err = core.json.encode(server_info)
    if not data then
        core.log.error("failed to encode server_info: ", err)
        return
    end

    local ok, err = common.internal_status:set("server_info", data)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
        return
    end
end


function _M.init_worker(attr)
    if core.config ~= require("apisix.core.config_etcd") then
        -- we don't need to report server info if etcd is not in use.
        return
    end


    local local_conf = core.config.local_conf()
    local deployment_role = core.table.try_read_attr(
                       local_conf, "deployment", "role")
    if deployment_role == "data_plane" then
        -- data_plane should not write to etcd
        return
    end

    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("failed to check plugin_attr: ", err)
        return
    end

    local report_ttl = attr and attr.report_ttl or default_report_ttl
    local start_at = ngx_time()

    local fn = function()
        local now = ngx_time()
        -- If ttl remaining time is less than half, then flush the ttl
        if now - start_at >= (report_ttl / 2) then
            start_at = now
            report(nil, report_ttl)
        end
    end

    if ngx_worker_id() == 0 then
        local ok, err = ngx_timer_at(0, report, report_ttl)
        if not ok then
            core.log.error("failed to create initial timer to report server info: ", err)
            return
        end
    end

    timers.register_timer("plugin#server-info", fn, true)

    core.log.info("timer update the server info ttl, current ttl: ", report_ttl)
end


return _M
