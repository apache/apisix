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
local core                            = require("apisix.core")
local redis_schema                    = require("apisix.utils.redis-schema")
local policy_to_additional_properties = redis_schema.schema
local plugin_name                     = "limit-req"
local str_format                      = string.format
local ipairs                          = ipairs

local limit_req_init = require("apisix.plugins.limit-req.init")


local schema = {
    type = "object",
    properties = {
        rate = {
            oneOf = {
                {type = "number", exclusiveMinimum = 0},
                {type = "string"},
            },
        },
        burst = {
            oneOf = {
                {type = "number", minimum = 0},
                {type = "string"},
            },
        },
        key = {type = "string"},
        key_type = {type = "string",
            enum = {"var", "var_combination"},
            default = "var",
        },
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    rate = {
                        oneOf = {
                            {type = "number", exclusiveMinimum = 0},
                            {type = "string"},
                        },
                    },
                    burst = {
                        oneOf = {
                            {type = "number", minimum = 0},
                            {type = "string"},
                        },
                    },
                    key = {type = "string"},
                },
                required = {"rate", "burst", "key"},
            },
        },
        policy = {
            type = "string",
            enum = {"redis", "redis-cluster", "local"},
            default = "local",
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        nodelay = {
            type = "boolean", default = false
        },
        allow_degradation = {type = "boolean", default = false}
    },
    oneOf = {
        {
            required = {"rate", "burst", "key"},
        },
        {
            required = {"rules"},
        }
    },
    ["if"] = {
        properties = {
            policy = {
                enum = {"redis"},
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    ["else"] = {
        ["if"] = {
            properties = {
                policy = {
                    enum = {"redis-cluster"},
                },
            },
        },
        ["then"] = policy_to_additional_properties["redis-cluster"],
    }
}


local _M = {
    version = 0.1,
    priority = 1001,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local keys = {}
    for _, rule in ipairs(conf.rules or {}) do
        if keys[rule.key] then
            return false, str_format("duplicate key '%s' in rules", rule.key)
        end
        keys[rule.key] = true
    end

    return true
end


function _M.access(conf, ctx)
    return limit_req_init.access(conf, ctx)
end


return _M
