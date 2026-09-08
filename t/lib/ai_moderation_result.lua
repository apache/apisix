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
local http = require("resty.http")
local sse = require("apisix.plugins.ai-transport.sse")
local _M = {}

function _M.setup()
    local test = require("lib.test_admin").test
    local core = require("apisix.core")
    local code, body = test("/apisix/admin/consumers", ngx.HTTP_PUT, [[{
        "username":"moderation-result",
        "plugins":{
            "key-auth":{"key":"moderation-result"},
            "ai-aliyun-content-moderation":{
                "endpoint":"http://127.0.0.1:6724","region_id":"cn-beijing",
                "access_key_id":"test-key","access_key_secret":"test-secret",
                "check_request":true,"check_response":true,
                "request_check_service":"query_security_check",
                "response_check_service":"response_security_check",
                "stream_check_mode":"final_packet","deny_message":"response rejected"
            }
        }
    }]])
    assert(code < 300, body)
    for id, route in ipairs({
        {"/chat", "openai"}, {"/v1/messages", "anthropic"},
        {"/v1/responses", "openai"}, {"/converted/v1/messages", "openai"}
    }) do
        local conf = {
            uri = route[1],
            plugins = {
                ["key-auth"] = {},
                ["ai-proxy"] = {
                    provider = route[2],
                    auth = {header = {Authorization = "Bearer test"}},
                    override = {endpoint = "http://127.0.0.1:6725"},
                    streaming_flush_interval_ms = 0,
                },
                ["serverless-post-function"] = {
                    phase = "log",
                    functions = {"return function(conf, ctx) "
                        .. "ngx.shared.test:set('tokens', "
                        .. "tonumber(ctx.var.llm_total_tokens) or 0); "
                        .. "ngx.shared.test:set('raw_usage', require('apisix.core').json.encode("
                        .. "ctx.llm_raw_usage or {})) end"},
                },
            },
        }
        code, body = test("/apisix/admin/routes/" .. id, ngx.HTTP_PUT,
                          core.json.encode(conf))
        assert(code < 300, body)
    end
end


function _M.check(case)
    local path = "/chat"
    local body = {model = "test-model", stream = true,
                  messages = {{role = "user", content = "hello"}}}
    if case.protocol == "anthropic" then
        path = "/v1/messages"
        body.max_tokens = 100
    elseif case.protocol == "responses" then
        path = "/v1/responses"
        body.messages = nil
        body.input = "hello"
    end
    if case.converted then
        path = "/converted" .. path
    end
    local res = assert(http.new():request_uri("http://127.0.0.1:" .. ngx.var.server_port .. path, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            apikey = "moderation-result",
            ["X-AI-Fixture"] = "aliyun/result-" .. case.fixture .. ".sse",
            ["X-Buffered"] = case.buffered and "true" or nil,
            ["X-Split-Done"] = case.split_done and "true" or nil,
        },
        body = core.json.encode(body),
    }))
    assert(res.status == 200, res.body)
    local expected_text = case.text or "kill you"
    for _, service in ipairs({"query_security_check", "response_security_check"}) do
        assert(ngx.shared.test:get(service .. "_calls") == 1, service .. ": expected one check")
    end
    assert(ngx.shared.test:get("response_security_check_content") == expected_text,
           "response scan did not receive all content")

    local events, remainder = sse.decode_buf(res.body)
    assert(remainder == "", "partial downstream event")
    local risk_count, done_count, start_count = 0, 0, 0
    local original = {}
    for i, event in ipairs(events) do
        if event.data == "[DONE]" or event.type == "message_stop"
           or event.type == "response.completed" then
            done_count = done_count + 1
            assert(i == #events, "event emitted after completion")
        end
        if event.type == "message_start" or event.type == "response.created" then
            start_count = start_count + 1
        end
        if event.data == "[DONE]" then
            goto CONTINUE
        end
        local data = assert(core.json.decode(event.data))
        if case.protocol == "chat" and not data.risk_level then
            for _, choice in ipairs(data.choices or {}) do
                if type(choice.delta.content) == "string" then
                    original[#original + 1] = choice.delta.content
                end
            end
        elseif event.type == "content_block_delta" then
            original[#original + 1] = data.delta.text
        elseif event.type == "response.output_text.delta" then
            original[#original + 1] = data.delta
        end

        if data.risk_level then
            risk_count = risk_count + 1
            assert(data.risk_level == (case.safe and "none" or "high"), "wrong risk")
            if case.protocol == "chat" then
                assert(i == #events - 1, "moderation result must precede DONE")
                assert(data.id == "chatcmpl-moderation", "changed completion identity")
                assert(data.model == "test-model" and data.created == 1700000000,
                       "changed completion metadata")
                assert(data.choices[1].delta.content == (case.safe and "" or "response rejected"),
                       "wrong denial text")
                assert(data.usage.prompt_tokens == 0 and data.usage.completion_tokens == 0
                       and data.usage.total_tokens == 0, "result usage must be zero")
            elseif case.protocol == "anthropic" then
                assert(event.type == "message_delta", "wrong Anthropic event")
                assert(data.deny_message == "response rejected", "missing denial text")
                assert(data.usage.output_tokens == (case.buffered and 8 or 0), "wrong usage")
            elseif case.protocol == "responses" then
                assert(event.type == "response.completed", "wrong Responses event")
                assert(data.deny_message == "response rejected", "missing denial text")
                assert(data.response.id == "resp_moderation", "changed response identity")
                assert(data.response.output[1].content[1].text == expected_text,
                       "completed output was replaced")
                if case.tokens then
                    assert(data.response.usage.total_tokens == case.tokens, "usage was replaced")
                end
            end
        end
        ::CONTINUE::
    end
    assert(table.concat(original) == expected_text, "original response text was changed")
    assert(risk_count == ((case.failure or case.eof) and 0 or 1), "wrong moderation result count")
    assert(done_count == (case.eof and 0 or 1), "wrong terminator count")
    if case.protocol ~= "chat" then
        assert(start_count == 1, "message/response start was replayed")
    end
    assert(ngx.shared.test:get("tokens") == (case.tokens or 0), "token accounting changed")
    if case.tokens then
        local raw = assert(core.json.decode(ngx.shared.test:get("raw_usage")))
        assert((raw.prompt_tokens or raw.input_tokens) == 10, "raw input usage changed")
        assert((raw.completion_tokens or raw.output_tokens) == 8, "raw output usage changed")
    end
end

return _M
