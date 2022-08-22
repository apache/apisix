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
local core       = require("apisix.core")
local expr       = require("resty.expr.v1")
local ipairs     = ipairs
local tonumber   = tonumber
local type       = type

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
                            type = "array",
                        },
                        minItems = 1,
                    },
                    actions = {
                        type = "array",
                        items = {
                            type = "array",
                            minItems = 2
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

local support_action = {
    ["return"] = true,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, rule in ipairs(conf.rules) do
        local ok, err = expr.new(rule.case)
        if not ok then
            return false, "failed to validate the 'case' expression: " .. err
        end

        local actions = rule.actions
        for _, action in ipairs(actions) do

            if not support_action[action[1]] then
                return false, "unsupported action: " .. action[1]
            end

            if action[1] == "return" then
                if not action[2].code then
                    return false, "bad actions, code is needed if action is return"
                end

                if type(action[2].code) ~= "number" then
                    return false, "bad code, the required type of code is number"
                end
            end
       end
    end

    return true
end


local function do_action(actions)
    for _, action in ipairs(actions) do
        if action[1] == "return" then
            local code = tonumber(action[2].code)
            return core.response.exit(code)
        end
   end
end


function _M.access(conf, ctx)
    local match_result
    for _, rule in ipairs(conf.rules) do
        local expr, _ = expr.new(rule.case)
        match_result = expr:eval(ctx.var)
        if match_result then
            do_action(rule.actions)
        end
    end
end


return _M
