--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
--
local base = require("apisix.plugins.ai-drivers.ai-driver-base")
local core = require("apisix.core")
local setmetatable = setmetatable

local _M = { name = "anthropic" }
local mt = { __index = setmetatable(_M, { __index = base }) }

function _M.new(opts)
    return setmetatable(opts or {}, mt)
end

function _M:transform_request(conf, request_table)
    local anthropic_body = {
        model = conf.model,
        messages = {},
        max_tokens = request_table.max_tokens or 1024, -- Anthropic requires max_tokens
    }

    -- Extract system prompt and map roles
    for _, msg in ipairs(request_table.messages) do
        if msg.role == "system" then
            anthropic_body.system = msg.content
        else
            core.table.insert(anthropic_body.messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = conf.api_key,
        ["anthropic-version"] = "2023-06-01", -- Required by Anthropic
    }

    return anthropic_body, headers
end

function _M:transform_response(response_body)
    local body = core.json.decode(response_body)
    if not body or not body.content then
        return nil, "invalid response from anthropic"
    end

    -- Convert back to OpenAI format
    return {
        id = body.id,
        object = "chat.completion",
        created = os.time(),
        model = body.model,
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = body.content[1].text,
                },
                finish_reason = "end_turn"
            }
        },
        usage = {
            prompt_tokens = body.usage.input_tokens,
            completion_tokens = body.usage.output_tokens,
            total_tokens = body.usage.input_tokens + body.usage.output_tokens
        }
    }
end

return _M
