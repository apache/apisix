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
local process = require("ngx.process")
local core = require("apisix.core")

local type = type
local ngx_time = ngx.time

local boot_time = os.time()
local internal_status = ngx.shared.internal_status

local _M = {}

if not internal_status then
    error("lua_shared_dict \"internal_status\" not configured")
end


local function is_privileged()
    return process.type() == "privileged agent" or process.type() == "single"
end

-- server information will be saved into shared memory only if the key
-- "server_info" not exist if excl is true.
local function save(data, excl)
    local handler = excl and internal_status.add or internal_status.set

    local ok, err = handler(internal_status, "server_info", data)
    if not ok then
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


local function report()
    local server_info, err = _M.get()
    if not server_info then
        core.log.error("failed to get server_info: ", err)
        return nil, err
    end

    if server_info.etcd_version == "unknown" then
        local res, err = core.etcd.server_version()
        if not res then
            core.log.error("failed to fetch etcd version: ", err)
            return nil, err

        elseif type(res.body) ~= "table" then
            core.log.error("failed to fetch etcd version: bad version info")
            return nil, "bad etcd version info"
        else
            server_info.etcd_version = res.body.etcdcluster
        end
    end

    server_info.last_report_time = ngx_time()

    local data, err = core.json.encode(server_info)
    if not data then
        core.log.error("failed to encode server_info: ", err)
        return nil, err
    end

    local key = "/data_plane/server_info/" .. server_info.id
    local ok, err = core.etcd.set(key, data, 180)
    if not ok then
        core.log.error("failed to report server info to etcd: ", err)
        return nil, err
    end

    local ok, err = save(data, false)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
        return nil, err
    end
end


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


function _M.init_worker()
    if not is_privileged() then
        return
    end

    local ok, err = encode_and_save(uninitialized_server_info(), true)
    if not ok then
        core.log.error("failed to encode and save server info: ", err)
    end

    local opts = {
        check_interval = 5, -- in seconds
    }

    if core.config ~= require("apisix.core.config_etcd") then
        return
    end

    -- only launch timer to report server info when config cener is etcd.
    local timer, err = core.timer.new("server info", report, opts)
    if not timer then
        core.log.error("failed to create timer to report server info ", err)
    end
end


function _M.get()
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


return _M
