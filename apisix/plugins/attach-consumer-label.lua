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
local plugin_name = "attach-consumer-label"

local schema = {
    type = "object",
    properties = {
        headers = {
            type = "object",
            additionalProperties = {
                type = "string",
                pattern = "^\\$.*"
            },
            minProperties = 1
        },
    },
    required = {"headers"},
}

local _M = {
    version = 0.1,
    priority = 2399,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.before_proxy(conf, ctx)
    -- check if the consumer is exists in the context
    if not ctx.consumer then
        return
    end

    local labels = ctx.consumer.labels
    core.log.info("consumer username: ", ctx.consumer.username, " labels: ",
            core.json.delay_encode(labels))
    if not labels then
        return
    end

    for header, label_key in pairs(conf.headers) do
        -- remove leading $ character
        local label_value = labels[label_key:sub(2)]
        core.request.set_header(ctx, header, label_value)
    end
end

return _M
