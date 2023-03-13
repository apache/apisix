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
local common = require("apisix.plugins.server-info.common")
local plugin_name = "server-info"

local schema = {
    type = "object",
}


local _M = {
    version = 0.1,
    priority = 990,
    name = plugin_name,
    schema = schema,
    scope = "global",
}


local function get_server_info()
    local info, err = common.get()
    if not info then
        core.log.error("failed to get server_info: ", err)
        return 500
    end

    return 200, info
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris ={"/v1/server_info"},
            handler = get_server_info,
        }
    }
end


function _M.init()
    core.log.warn("server-info plugin was moved into APISIX core, no need to enable it explicitly")
end


return _M
