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
local load_time = os.time()

local internal_status = ngx.shared["internal-status"]
if not internal_status then
    error("lua_shared_dict \"internal-status\" not configured")
end


local _M = {
    internal_status = internal_status,
}


local function get_boot_time()
    local time, err = internal_status:get("server_info:boot_time")
    if err ~= nil then
        core.log.error("failed to get boot_time from shdict: ", err)
        return load_time
    end

    if time ~= nil then
        return time
    end

    local _, err = internal_status:set("server_info:boot_time", load_time)
    if err ~= nil then
        core.log.error("failed to save boot_time to shdict: ", err)
    end

    return load_time
end


local function uninitialized_server_info()
    local boot_time = get_boot_time()
    return {
        etcd_version     = "unknown",
        hostname         = core.utils.gethostname(),
        id               = core.id.get(),
        version          = core.version.VERSION,
        boot_time        = boot_time,
    }
end


function _M.get()
    local data, err = internal_status:get("server_info")
    if err ~= nil then
        core.log.error("get error: ", err)
        return nil, err
    end

    if not data then
        return uninitialized_server_info()
    end

    local server_info, err = core.json.decode(data)
    if not server_info then
        core.log.error("failed to decode server_info: ", err)
        return nil, err
    end

    return server_info
end


return _M
