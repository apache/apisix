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
local limit_count = require("apisix.plugins.limit-count.init")
local expr        = require("resty.expr.v1")
local ipairs      = ipairs

local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    case = {
                        type = "array",
                        items = {
                            anyOf = {
                                {
                                    type = "array",
                                },
                                {
                                    type = "string",
                                },
                            }
                        },
                        minItems = 1,
                    },
                    actions = {
                        type = "array",
                        items = {
                            type = "array",
                            minItems = 1
                        }
                    }
                },
                required = {"case", "actions"}
            }
        }
    }
}

local plugin_name = "workflow"

local _M = {
    version = 0.1,
    priority = 1006,
    name = plugin_name,
    schema = schema
}


local return_schema = {
    type = "object",
    properties = {
        code = {
            type = "integer",
            minimum = 100,
            maximum = 599
        }
    },
    required = {"code"}
}


local function check_return_schema(conf)
    local ok, err = core.schema.check(return_schema, conf)
    if not ok then
        return false, err
    end
    return true
end


local function exit(conf)
    return conf.code, {error_msg = "rejected by workflow"}
end


local function rate_limit(conf, ctx)
    return limit_count.rate_limit(conf, ctx)
end


local support_action = {
    ["return"] = {
        handler        = exit,
        check_schema   = check_return_schema,
    },
    ["limit-count"] = {
        handler        = rate_limit,
        check_schema   = limit_count.check_schema,
    }
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for idx, rule in ipairs(conf.rules) do
        local ok, err = expr.new(rule.case)
        if not ok then
            return false, "failed to validate the 'case' expression: " .. err
        end

        local actions = rule.actions
        for _, action in ipairs(actions) do

            if not support_action[action[1]] then
                return false, "unsupported action: " .. action[1]
            end

            -- use the action's idx as an identifier to isolate between confs
            action[2]["_vid"] = idx
            local ok, err = support_action[action[1]].check_schema(action[2], plugin_name)
            if not ok then
                return false, "failed to validate the '" .. action[1] .. "' action: " .. err
            end
       end
    end

    return true
end


function _M.access(conf, ctx)
    local match_result
    for _, rule in ipairs(conf.rules) do
        local expr, _ = expr.new(rule.case)
        match_result = expr:eval(ctx.var)
        if match_result then
            -- only one action is currently supported
            local action = rule.actions[1]
            return support_action[action[1]].handler(action[2], ctx)
        end
    end
end


return _M
