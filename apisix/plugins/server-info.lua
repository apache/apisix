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

local ngx_time = ngx.time
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id
local type = type

local plugin_name = "server-info"
local boot_time = os.time()
local current_timer
local schema = {
    type = "object",
    additionalProperties = false,
}
local attr_schema = {
    type = "object",
    properties = {
        report_interval = {
            type = "integer",
            description = "server info reporting interval (unit: second)",
            default = 60,
            minimum = 5,
        }
    }
}

local internal_status = ngx.shared.internal_status
if not internal_status then
    error("lua_shared_dict \"internal_status\" not configured")
end


local _M = {
    version = 0.1,
    priority = 990,
    name = plugin_name,
    schema = schema,
}


local function uninitialized_server_info()
    return {
        etcd_version     = "unknown",
        hostname         = core.utils.gethostname(),
        id               = core.id.get(),
        version          = core.version.VERSION,
        up_time          = ngx_time() - boot_time,
        last_report_time = -1,
    }
end


-- server information will be saved into shared memory only if the key
-- "server_info" not exist if excl is true.
local function save(data, excl)
    local handler = excl and internal_status.add or internal_status.set

    local ok, err = handler(internal_status, "server_info", data)
    if not ok then
        if excl and err == "exists" then
            return true
        end

        return nil, err
    end

    return true
end


local function encode_and_save(server_info, excl)
    local data, err = core.json.encode(server_info)
    if not data then
        return nil, err
    end

    return save(data, excl)
end


local function get()
    local data, err = internal_status:get("server_info")
    if err ~= nil then
        return nil, err
    end

    if not data then
        return uninitialized_server_info()
    end

    local server_info, err = core.json.decode(data)
    if not server_info then
        return nil, err
    end

    server_info.up_time = ngx_time() - boot_time
    return server_info
end


local function get_server_info()
    local server_info, err = get()
    if not server_info then
        core.log.error("failed to get server_info: ", err)
        return 500, err
    end

    return 200, core.json.encode(server_info)
end


local function report()
    local server_info, err = get()
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
            server_info.etcd_version = res.body.etcdcluster
        end
    end

    server_info.last_report_time = ngx_time()

    local data, err = core.json.encode(server_info)
    if not data then
        core.log.error("failed to encode server_info: ", err)
        return
    end

    local key = "/data_plane/server_info/" .. server_info.id
    local ok, err = core.etcd.set(key, data, 180)
    if not ok then
        core.log.error("failed to report server info to etcd: ", err)
        return
    end

    local ok, err = save(data, false)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
        return
    end
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.init()
    if ngx_worker_id() ~= 0 then
        -- only let the No.0 worker to launch timer for server info reporting.
        return
    end

    local ok, err = encode_and_save(uninitialized_server_info(), true)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
    end

    if core.config ~= require("apisix.core.config_etcd") then
        -- we don't need to report server info if etcd is not in use.
        return
    end

    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr",
                                          plugin_name)
    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("failed to check plugin_attr: ", err)
        return
    end

    local report_interval = attr.report_interval

    -- we don't use core.timer and the apisix.timers here for:
    -- 1. core.timer is not cancalable, timers will be leaked if plugin
    -- reloading happens.
    -- 2. the background timer in apisix.timers fires per 500 milliseconds, if
    -- report_interval is not multiple of 0.5, the real report interval will be
    -- inaccurate over time.
    local fn
    fn = function(premature, timer)
        if premature or timer.cancelled then
            return
        end

        report()

        if not timer.cancelled then
            local ok, err = ngx_timer_at(report_interval, fn, timer)
            if not ok then
                core.log.error("failed to create timer to report server info: ", err)
            end

        else
            core.log.warn("server info report timer is cancelled")
        end
    end

    current_timer = {
        cancelled = false
    }

    local ok, err = ngx_timer_at(0, fn, current_timer)
    if ok then
        core.log.info("timer created to report server info, interval: ",
                      report_interval)
    else
        core.log.error("failed to create timer to report server info: ", err)
    end
end


function _M.destory()
    if ngx_worker_id() ~= 0 then
        -- timer exists only in the No.0 worker.
        return
    end

    if current_timer then
        current_timer.cancelled = true
        current_timer = nil
    end
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/server_info",
            handler = get_server_info,
        },
    }
end


return _M
