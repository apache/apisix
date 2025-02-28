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
local ngx = ngx
local ipairs = ipairs
local table = table

local plugin_name = "ai-prompt-guard"

local schema = {
    type = "object",
    properties = {
        match_all_roles = {
            type = "boolean",
            default = false,
        },
        match_all_conversation_history = {
            type = "boolean",
            default = false,
        },
        allow_patterns = {
            type = "array",
            items = {type = "string"},
            default = {},
        },
        deny_patterns = {
            type = "array",
            items = {type = "string"},
            default = {},
        },
    },
}

local _M = {
    version = 0.1,
    priority = 1072,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function get_content_to_check(conf, messages)
    local contents = {}
    if conf.match_all_conversation_history then
        for _, msg in ipairs(messages) do
            if msg.content then
                core.table.insert(contents, msg.content)
            end
        end
    else
        if #messages > 0 then
            local last_msg = messages[#messages]
            if last_msg.content then
                core.table.insert(contents, last_msg.content)
            end
        end
    end
    return table.concat(contents, " ")
end

function _M.access(conf, ctx)
    local body = core.request.get_body()
    if not body then
        core.log.error("Empty request body")
        return 400, {message = "Empty request body"}
    end

    local json_body, err = core.json.decode(body)
    if err then
        return 400, {message = err}
    end


    local messages = json_body.messages or {}
    if not conf.match_all_roles and messages and messages[#messages].role ~= "user" then
        return
    end
    local content_to_check = get_content_to_check(conf, messages)

    -- Allow patterns check
    if #conf.allow_patterns > 0 then
        local any_allowed = false
        for _, pattern in ipairs(conf.allow_patterns) do
            if ngx.re.find(content_to_check, pattern, "jou") then
                any_allowed = true
                break
            end
        end
        if not any_allowed then
            return 400, {message = "Request doesn't match allow patterns"}
        end
    end

    -- Deny patterns check
    for _, pattern in ipairs(conf.deny_patterns) do
        if ngx.re.find(content_to_check, pattern, "jou") then
            return 400, {message = "Request contains prohibited content"}
        end
    end
end

return _M
