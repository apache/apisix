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

local core        = require("apisix.core")
local schema_mod  = require("apisix.plugins.ai-cache.schema")

local plugin_name = "ai-cache"

local _M = {
    -- ai-proxy = 1040, ai-proxy-multi = 1041, proxy-cache = 1085.
    -- ai-cache must run before ai-proxy so a hit can short-circuit
    -- before the upstream request is built (RFC § 2.3).
    version        = 0.1,
    priority       = 1086,
    name           = plugin_name,
    schema         = schema_mod.schema,
    encrypt_fields = schema_mod.encrypt_fields,
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end

return _M
