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
local core          = require("apisix.core")
local binding       = require("apisix.plugins.ai-protocols.binding")
local body          = require("apisix.plugins.ai-prompt.body")
local prompt_schema = require("apisix.plugins.ai-prompt.schema")
local protocols     = require("apisix.plugins.ai-protocols")

local schema = {
    type = "object",
    properties = {
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum request body size in bytes buffered into "
                       .. "memory; larger request bodies are rejected",
        },
        prepend = prompt_schema.messages,
        append = prompt_schema.messages,
        fail_mode = binding.schema_property("skip"),
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


function _M.rewrite(conf, ctx)
    local body_tab, status, err = body.read(conf.max_req_body_size)
    if not body_tab then
        return status, err
    end

    local protocol_name = protocols.detect(body_tab, ctx)
    if not protocol_name or protocol_name == "passthrough"
       or protocol_name == "openai-embeddings" then
        local handled, code, response = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "request body does not match a supported chat protocol",
            400, {message = "Request format not recognized by ai-prompt-decorator"})
        if handled then
            return code, response
        end
        return
    end

    local protocol = protocols.get(protocol_name)
    protocol.prepend_messages(body_tab, conf.prepend)
    protocol.append_messages(body_tab, conf.append)

    return body.write(ctx, body_tab)
end


return _M
