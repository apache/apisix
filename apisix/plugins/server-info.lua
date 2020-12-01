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
local server_info = require("apisix.server_info")
local core = require("apisix.core")

local plugin_name = "server-info"
local schema = {
    type = "object",
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}


local function get_server_info()
    local server_info, err = server_info.get()
    if not server_info then
        core.log.error("failed to get server_info: ", err)
        return 500, err
    end

    return 200, core.json.encode(server_info)
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
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
