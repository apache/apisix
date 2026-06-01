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
local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")
local ngx   = ngx

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
        return nil, { message = "could not get body: " .. (err or "request body is empty") }
    end

    local body_tab, err = core.json.decode(body)
    if not body_tab then
        return nil, { message = "could not parse JSON request body: " .. (err or "invalid JSON") }
    end

    return body_tab
end


function _M.rewrite(conf, ctx)
    local body_tab, err = get_request_body_table()
    if not body_tab then
        return 400, err
    end

    protocols.prepend_messages(body_tab, ctx, conf.prepend)
    protocols.append_messages(body_tab, ctx, conf.append)

    local new_jbody, err = core.json.encode(body_tab)
    if not new_jbody then
        return 500, { message = "failed to parse modified JSON request body: " .. err }
    end

    ngx.req.set_body_data(new_jbody)
end


return _M
