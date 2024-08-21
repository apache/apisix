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
local core  = require("apisix.core")
local ngx   = ngx
local pairs = pairs


local prompt_schema = {
    properties = {
        role = {
            type = "string",
            enum = { "system", "user", "assistant" }
        },
        content = {
            type = "string",
            minLength = 1,
        }
    },
    required = { "role", "content" }
}

local prompts = {
    type = "array",
    items = prompt_schema
}

local schema = {
    type = "object",
    properties = {
        prepend = prompts,
        append = prompts,
    },
    anyOf = {
        { required = { "prepend" } },
        { required = { "append" } },
        { required = { "append", "prepend" } },
    },
}


local _M = {
    version  = 0.1,
    priority = 1070,
    name     = "ai-prompt-decorator",
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_request_body_table()
    local body, err = core.request.get_body()
    if not body then
        return nil, { message = "could not get body: " .. err }
    end

    local body_tab, err = core.json.decode(body)
    if not body_tab then
        return nil, { message = "could not get parse JSON request body: ", err }
    end

    return body_tab
end


local function decorate(conf, body_tab)
    local new_messages = conf.prepend or {}
    for _, message in pairs(body_tab.messages) do
        core.table.insert_tail(new_messages, message)
    end

    for _, message in pairs(conf.append or {}) do
        core.table.insert_tail(new_messages, message)
    end

    body_tab.messages = new_messages
end


function _M.rewrite(conf, ctx)
    local body_tab, err = get_request_body_table()
    if not body_tab then
        return 400, err
    end

    decorate(conf, body_tab) -- will decorate body_tab in place

    local new_jbody, err = core.json.encode(body_tab)
    if not new_jbody then
        return 500, { message = "failed to parse modified JSON request body: ", err }
    end

    ngx.req.set_body_data(new_jbody)
end


return _M
