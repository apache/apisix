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

local schema = {
    type = "object",
    properties = {
    }
}


local plugin_name = "uri-blocker"

local _M = {
    version = 0.1,
    priority = 2900,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return true
end


function _M.rewrite(conf, ctx)
    core.respond.exit(400)
end


return _M
