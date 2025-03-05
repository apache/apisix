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
local re_compile  = require("resty.core.regex").re_match_compile
local re_find = ngx.re.find

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
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    -- Validate allow_patterns
    for _, pattern in ipairs(conf.allow_patterns) do
        local compiled = re_compile(pattern, "jou")
        if not compiled then
            return false, "invalid allow_pattern: " .. pattern
        end
    end

    -- Validate deny_patterns
    for _, pattern in ipairs(conf.deny_patterns) do
        local compiled = re_compile(pattern, "jou")
        if not compiled then
            return false, "invalid deny_pattern: " .. pattern
        end
    end

    return true
end

local function get_content_to_check(conf, messages)
    if conf.match_all_conversation_history then
        return messages
    end
    local contents = {}
    if #messages > 0 then
        local last_msg = messages[#messages]
        if last_msg then
            core.table.insert(contents, last_msg)
        end
    end
    return contents
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
    messages = get_content_to_check(conf, messages)
    if not conf.match_all_roles then
        -- filter to only user messages
        local new_messages = {}
        for _, msg in ipairs(messages) do
            if not msg then
                return 400, {message = "request doesn't contain messages"}
            end
            if msg.role == "user" then
                core.table.insert(new_messages, msg)
            end
        end
        messages = new_messages
    end
    if #messages == 0 then --nothing to check
        return 200
    end
    -- extract only messages
    local content = {}
    for _, msg in ipairs(messages) do
        if not msg then
            return 400, {message = "request doesn't contain messages"}
        end
        if msg.content then
            core.table.insert(content, msg.content)
        end
    end
    local content_to_check = table.concat(content, " ")
     -- Allow patterns check
     if #conf.allow_patterns > 0 then
        local any_allowed = false
        for _, pattern in ipairs(conf.allow_patterns) do
            if re_find(content_to_check, pattern, "jou") then
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
        if re_find(content_to_check, pattern, "jou") then
            return 400, {message = "Request contains prohibited content"}
        end
    end
end

return _M
