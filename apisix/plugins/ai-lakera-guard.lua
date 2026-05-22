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
local schema_mod = require("apisix.plugins.ai-lakera-guard.schema")


local plugin_name = "ai-lakera-guard"


local _M = {
    version  = 0.1,
    priority = 1028,
    name     = plugin_name,
    schema   = schema_mod.schema,
}


function _M.check_schema(conf)
    return schema_mod.check_schema(conf)
end


function _M.access(conf, ctx)
    if not ctx.ai_client_protocol then
        return 500, "ai-lakera-guard plugin must be used with " ..
                    "ai-proxy or ai-proxy-multi plugin"
    end
end


return _M
