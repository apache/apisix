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
local ngx_encode_base64 = ngx.encode_base64
local plugin_name, plugin_version, priority = "openfunction", 0.1, -1902

local openfunction_authz_schema = {
    service_token = {type = "string"}
}

local function request_processor(conf, ctx, params)
    local headers = params.headers or {}
    -- setting authorization headers if authorization.service_token exists
    if  conf.authorization and conf.authorization.service_token then
        headers["authorization"] = "Basic " .. ngx_encode_base64(conf.authorization.service_token)
    end

    params.headers = headers
end

return require("apisix.plugins.serverless.generic-upstream")(plugin_name,
        plugin_version, priority, request_processor, openfunction_authz_schema)
