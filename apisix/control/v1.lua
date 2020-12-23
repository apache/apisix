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
local plugin = require("apisix.plugin")


local _M = {}


function _M.schema()
    local schema = {
        main = {
            consumer = core.schema.consumer,
            global_rule = core.schema.global_rule,
            plugins = core.schema.plugins,
            proto = core.schema.proto,
            route = core.schema.route,
            service = core.schema.service,
            ssl = core.schema.ssl,
            stream_route = core.schema.stream_route,
            upstream = core.schema.upstream,
        },
        plugins = plugin.get_all({
            version = true,
            priority = true,
            schema = true,
            metadata_schema = true,
            consumer_schema = true,
            type = true,
        }),
    }
    return 200, schema
end


return {
    -- /v1/schema
    {
        methods = {"GET"},
        uris = {"/schema"},
        handler = _M.schema,
    }
}
