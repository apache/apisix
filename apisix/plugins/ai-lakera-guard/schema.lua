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
        direction = {
            type = "string",
            enum = {"input", "output", "both"},
            default = "input",
        },
        action = {
            type = "string",
            enum = {"block", "alert"},
            default = "block",
        },
        endpoint = {
            type = "object",
            properties = {
                url = {
                    type = "string",
                    default = "https://api.lakera.ai/v2/guard",
                },
                api_key = {type = "string", minLength = 1},
                timeout_ms = {type = "integer", minimum = 1, default = 1000},
                ssl_verify = {type = "boolean", default = true},
                keepalive = {type = "boolean", default = true},
                keepalive_pool = {type = "integer", minimum = 1, default = 30},
                keepalive_timeout_ms = {
                    type = "integer",
                    minimum = 1000,
                    default = 60000,
                },
            },
            required = {"api_key"},
        },
        project_id = {type = "string", minLength = 1},
        response_buffer_size = {type = "integer", minimum = 1, default = 128},
        response_buffer_max_age_ms = {
            type = "integer",
            minimum = 1,
            default = 3000,
        },
        reveal_failure_categories = {type = "boolean", default = false},
        fail_open = {type = "boolean", default = false},
        on_block = {
            type = "object",
            properties = {
                status = {
                    type = "integer",
                    minimum = 100,
                    maximum = 599,
                    default = 200,
                },
                message = {
                    type = "string",
                    default = "Request blocked by security guard",
                },
            },
            default = {
                status = 200,
                message = "Request blocked by security guard",
            },
        },
    },
    encrypt_fields = {"endpoint.api_key"},
    required = {"endpoint"},
}


local _M = {}


_M.schema = schema


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


return _M
