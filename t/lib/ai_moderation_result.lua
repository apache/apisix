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
                        .. "require('lib.ai_moderation_result').record_usage(ctx) end"},
                },
            },
        }
        code, body = test("/apisix/admin/routes/" .. id, ngx.HTTP_PUT,
                          core.json.encode(conf))
        assert(code < 300, body)
    end
end


function _M.record_usage(ctx)
    local request_id = ctx.var.http_x_result_request_id
    assert(ngx.shared.test:set("accounting:" .. request_id, core.json.encode({
        tokens = tonumber(ctx.var.llm_total_tokens) or 0,
        raw_usage = ctx.llm_raw_usage or {},
    })))
end


function _M.check(case)
    local request_id = require("resty.jit-uuid").generate_v4()
    local accounting_key = "accounting:" .. request_id
    ngx.shared.test:delete(accounting_key)
    for _, service in ipairs({"query_security_check", "response_security_check"}) do
        ngx.shared.test:delete(service .. "_calls")
        ngx.shared.test:delete(service .. "_content")
    end
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
            ["X-Result-Request-ID"] = request_id,
            ["X-AI-Fixture"] = "aliyun/result-" .. case.fixture .. ".sse",
            ["X-Buffered"] = case.buffered and "true" or nil,
            ["X-Split-Done"] = case.split_done and "true" or nil,
        },
        body = core.json.encode(body),
    }))
    assert(res.status == 200, res.body)
    if case.split_done then
        assert(res.body:sub(1, 17) == ": keep-alive\r\n\r\n\n",
               "complete-frame dispatch changed comments or blank lines")
    end
    local expected_text = case.text or "kill you"
    for _, service in ipairs({"query_security_check", "response_security_check"}) do
        local expected_calls = case.error and not case.scanned
                               and service == "response_security_check" and 0 or 1
        assert((ngx.shared.test:get(service .. "_calls") or 0) == expected_calls,
               service .. ": wrong scan count")
    end
    assert(ngx.shared.test:get("response_security_check_content") ==
           ((not case.error or case.scanned) and expected_text or nil),
           "response scan did not receive all content")

    if case.error then
        assert(res.body:find(case.error_text or "stream failed", 1, true),
               "upstream error was lost")
    end
    local events, remainder = sse.decode_buf(res.body)
    assert(remainder == "", "partial downstream event")
    local risk_count, done_count, start_count = 0, 0, 0
    local original = {}
    local finish_reason
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
        if case.protocol == "chat" and (case.tokens or not data.risk_level) then
            for _, choice in ipairs(data.choices or {}) do
                if choice.finish_reason ~= core.json.null then
                    finish_reason = choice.finish_reason or finish_reason
                end
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
            assert(data.deny_message == (case.safe and "" or "response rejected"),
                   "missing top-level denial message")
            if case.protocol == "chat" and not case.tokens then
                assert(i == #events - 1, "moderation result must precede DONE")
                assert(type(data.id) == "string" and type(data.created) == "number",
                       "invalid result metadata")
                assert(data.model == "test-model", "invalid result model")
                assert(data.choices[1].finish_reason == core.json.null,
                       "moderation result must not replace the finish reason")
                assert(data.choices[1].delta.content == (case.safe and "" or "response rejected"),
                       "wrong denial text")
                assert(data.usage.prompt_tokens == 0 and data.usage.completion_tokens == 0
                       and data.usage.total_tokens == 0, "result usage must be zero")
            elseif case.protocol == "anthropic" then
                assert(event.type == "message_delta" or event.type == "content_block_delta",
                       "wrong Anthropic event")
                if event.type ~= "message_delta" then
                    goto CONTINUE
                end
                if case.missing_stop then
                    assert(data.delta == core.json.null, "original delta was replaced")
                    goto CONTINUE
                end
                assert(type(data.delta) == "table", "invalid Anthropic result delta")
                if case.stop_sequence then
                    assert(data.delta.stop_reason == "stop_sequence"
                           and data.delta.stop_sequence == case.stop_sequence,
                           "original Anthropic stop information was changed")
                end
                assert(data.usage.output_tokens == (case.tokens and 8 or 0), "wrong usage")
            elseif case.protocol == "responses" then
                assert(event.type == "response.completed", "wrong Responses event")
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
    if case.finish_reason then
        assert(finish_reason == case.finish_reason, "original finish reason was changed")
    end
    if case.failure or case.eof or (case.error and not case.scanned) then
        assert(risk_count == 0, "unexpected moderation result")
    elseif case.tokens then
        assert(risk_count > 0, "missing in-place moderation result")
    else
        assert(risk_count == 1, "wrong injected result count")
    end
    assert(done_count == ((case.eof or case.error) and 0 or 1), "wrong terminator count")
    if case.protocol ~= "chat" then
        assert(start_count == 1, "message/response start was replayed")
    end
    local deadline = ngx.now() + 1
    local accounting
    repeat
        accounting = ngx.shared.test:get(accounting_key)
        if accounting then
            break
        end
        ngx.sleep(0.01)
    until ngx.now() >= deadline
    assert(accounting, "log phase did not publish this request's accounting")
    accounting = assert(core.json.decode(accounting))
    ngx.shared.test:delete(accounting_key)
    assert(accounting.tokens == (case.tokens or 0), "token accounting changed")
    if case.tokens then
        local raw = accounting.raw_usage
        assert((raw.prompt_tokens or raw.input_tokens) == 10, "raw input usage changed")
        assert((raw.completion_tokens or raw.output_tokens) == 8, "raw output usage changed")
    end
end

return _M
