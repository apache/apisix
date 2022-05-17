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
        faults = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    commands = {
                        type = "array",
                        minItems = 1,
                        items = {
                            type = "string"
                        },
                    },
                    key = {
                        type = "string",
                        minLength = 1,
                    },
                    delay = {
                        type = "number",
                        description = "additional delay in seconds",
                    }
                },
                required = {"commands", "delay"}
            },
        },
    },
}

local _M = {}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


return _M
