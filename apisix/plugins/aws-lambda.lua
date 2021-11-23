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

local plugin_name, plugin_version, priority = "aws-lambda", 0.1, -1901

local aws_authz_schema = {
    type = "object",
    properties = {
        apikey = {type = "string"},
        -- more to be added soon
    }
}

local function preprocess_headers(conf, ctx, headers)
    -- set authorization headers if not already set by the client
    -- we are following not to overwrite the authz keys
    if not headers["x-api-key"] then
        if conf.authorization then
            headers["x-api-key"] = conf.authorization.apikey
        end
    end
end


return require("apisix.plugins.serverless.generic-upstream")(plugin_name,
        plugin_version, priority, preprocess_headers, aws_authz_schema)
