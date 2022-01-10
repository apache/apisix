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

local plugin = require("apisix.plugin")
local plugin_name, plugin_version, priority = "azure-functions", 0.1, -1900

local azure_authz_schema = {
    type = "object",
    properties = {
        apikey = {type = "string"},
        clientid = {type = "string"}
    }
}

local metadata_schema = {
    type = "object",
    properties = {
        master_apikey = {type = "string", default = ""},
        master_clientid = {type = "string", default = ""}
    }
}

local function request_processor(conf, ctx, params)
    local headers = params.headers or {}
    -- set authorization headers if not already set by the client
    -- we are following not to overwrite the authz keys
    if not headers["x-functions-key"] and
            not headers["x-functions-clientid"] then
        if conf.authorization then
            headers["x-functions-key"] = conf.authorization.apikey
            headers["x-functions-clientid"] = conf.authorization.clientid
        else
            -- If neither api keys are set with the client request nor inside the plugin attributes
            -- plugin will fallback to the master key (if any) present inside the metadata.
            local metadata = plugin.plugin_metadata(plugin_name)
            if metadata then
                headers["x-functions-key"] = metadata.value.master_apikey
                headers["x-functions-clientid"] = metadata.value.master_clientid
            end
        end
    end

    params.headers = headers
end


return require("apisix.plugins.serverless.generic-upstream")(plugin_name,
        plugin_version, priority, request_processor, azure_authz_schema, metadata_schema)
