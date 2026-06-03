#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set route for request conversion tests (capture forwarded body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Route that echoes the forwarded body (to verify request conversion)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "openai-backend",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer test-token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4o"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:1980"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: simple text message conversion
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/(?=.*"type":"message")(?=.*"type":"text")(?=.*"stop_reason":"end_turn")/



=== TEST 3: system prompt as string
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":512,"system":"You are helpful.","messages":[{"role":"user","content":"Hi"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/"type":"message"/
--- no_error_log
[error]



=== TEST 4: system prompt as content blocks array with cache_control
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":512,"system":[{"type":"text","text":"You are a coding assistant.","cache_control":{"type":"ephemeral"}},{"type":"text","text":"Always write tests."}],"messages":[{"role":"user","content":"Hi"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/"type":"message"/
--- no_error_log
[error]



=== TEST 5: tool_use in assistant message → tool_calls conversion
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"What is the weather?"},{"role":"assistant","content":[{"type":"tool_use","id":"call_abc","name":"get_weather","input":{"location":"SF"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"call_abc","content":"Sunny, 72F"}]}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/"type":"message"/
--- no_error_log
[error]



=== TEST 6: response with tool_calls → Anthropic tool_use blocks
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Get the weather"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-with-tool-calls.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"type":"tool_use")(?=.*"name":"get_weather")(?=.*"id":"call_abc123")(?=.*"stop_reason":"tool_use")/
--- no_error_log
[error]



=== TEST 7: response with reasoning_content → thinking block
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Think about this"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-with-reasoning.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"type":"thinking")(?=.*"thinking":"Let me think step by step)(?=.*"signature":"")(?=.*"type":"text")(?=.*The answer is 42)/
--- no_error_log
[error]



=== TEST 8: cached_tokens deducted from input_tokens
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-with-reasoning.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"input_tokens":20)(?=.*"cache_read_input_tokens":10)(?=.*"cache_creation_input_tokens":5)/
--- no_error_log
[error]



=== TEST 9: error response passthrough
--- request
POST /v1/messages
{"model":"nonexistent","max_tokens":1024,"messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-error.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"type":"error")(?=.*"invalid_request_error")(?=.*model does not exist)/
--- no_error_log
[error]



=== TEST 10: response with multiple tool_calls + text → text block + tool_use blocks
--- request
POST /v1/messages
{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"check weather and time"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-with-multiple-tool-calls.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"type":"text")(?=.*Let me check both)(?=.*"type":"tool_use")(?=.*get_weather)(?=.*get_time)/
--- no_error_log
[error]



=== TEST 11: null prompt_tokens_details does not crash
--- request
POST /v1/messages
{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/null-details.json
--- error_code: 200
--- response_body_like eval
qr/(?s)(?=.*"input_tokens":10)(?=.*"output_tokens":5)/
--- no_error_log
[error]



=== TEST 12: null usage object handled gracefully
--- request
POST /v1/messages
{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/null-usage.json
--- error_code: 200
--- response_body_like eval
qr/"input_tokens":0/
--- no_error_log
[error]



=== TEST 13: null message fields handled gracefully
--- request
POST /v1/messages
{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/null-message.json
--- error_code: 200
--- response_body_like eval
qr/"type":"text"/
--- no_error_log
[error]



=== TEST 14: null function in tool_calls handled gracefully
--- request
POST /v1/messages
{"model":"test-model","max_tokens":100,"messages":[{"role":"user","content":"call tool"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/null-function.json
--- error_code: 200
--- response_body_like eval
qr/"type":"tool_use"/
--- no_error_log
[error]



=== TEST 15: whitelist body - unknown fields are NOT forwarded
Verify that anthropic-specific fields like metadata, top_k, thinking (raw),
output_config do NOT appear in the converted request.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local request = {
                model = "claude-sonnet-4-20250514",
                max_tokens = 1024,
                metadata = { user_id = "test" },
                top_k = 5,
                thinking = { type = "enabled", budget_tokens = 8000 },
                unknown_field = "should not appear",
                messages = {
                    { role = "user", content = "Hello" }
                }
            }

            local ctx = { var = {} }
            local result, err = converter.convert_request(request, ctx)
            if not result then
                ngx.say("ERROR: " .. (err or "nil"))
                return
            end

            -- These fields should NOT be present
            local leaked = {}
            for _, field in ipairs({"metadata", "top_k", "unknown_field"}) do
                if result[field] ~= nil then
                    table.insert(leaked, field)
                end
            end
            if #leaked > 0 then
                ngx.say("LEAKED: " .. table.concat(leaked, ", "))
                return
            end

            -- thinking should be converted to reasoning_effort, not passed raw
            if result.thinking ~= nil then
                ngx.say("LEAKED: thinking (raw)")
                return
            end
            if result.reasoning_effort ~= "medium" then
                ngx.say("reasoning_effort wrong: " .. tostring(result.reasoning_effort))
                return
            end

            -- max_tokens should become max_completion_tokens
            if result.max_tokens ~= nil then
                ngx.say("LEAKED: max_tokens")
                return
            end
            if result.max_completion_tokens ~= 1024 then
                ngx.say("max_completion_tokens wrong: " .. tostring(result.max_completion_tokens))
                return
            end

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 16: tool_choice conversion (auto, any, tool, none)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- auto
            local r = converter.convert_request({
                model = "claude-sonnet-4-20250514", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "f", input_schema = {} }},
                tool_choice = { type = "auto" },
            }, ctx)
            assert(r.tool_choice == "auto", "auto failed: " .. tostring(r.tool_choice))

            -- any → required
            r = converter.convert_request({
                model = "claude-sonnet-4-20250514", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "f", input_schema = {} }},
                tool_choice = { type = "any" },
            }, ctx)
            assert(r.tool_choice == "required", "any failed: " .. tostring(r.tool_choice))

            -- none
            r = converter.convert_request({
                model = "claude-sonnet-4-20250514", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "f", input_schema = {} }},
                tool_choice = { type = "none" },
            }, ctx)
            assert(r.tool_choice == "none", "none failed: " .. tostring(r.tool_choice))

            -- tool → {type:"function", function:{name:"X"}}
            r = converter.convert_request({
                model = "claude-sonnet-4-20250514", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "search", input_schema = {} }},
                tool_choice = { type = "tool", name = "search" },
            }, ctx)
            assert(type(r.tool_choice) == "table", "tool failed")
            assert(r.tool_choice.type == "function", "tool type")
            assert(r.tool_choice["function"].name == "search", "tool name")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 17: disable_parallel_tool_use → parallel_tool_calls=false
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "claude-sonnet-4-20250514", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "f", input_schema = {} }},
                tool_choice = { type = "auto", disable_parallel_tool_use = true },
            }, ctx)
            assert(r.parallel_tool_calls == false, "parallel_tool_calls not false")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 18: thinking config budget thresholds
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- low: < 4096
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                thinking = { type = "enabled", budget_tokens = 2000 },
            }, ctx)
            assert(r.reasoning_effort == "low", "low: " .. tostring(r.reasoning_effort))

            -- medium: 4096 <= x < 16384
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                thinking = { type = "enabled", budget_tokens = 8000 },
            }, ctx)
            assert(r.reasoning_effort == "medium", "medium: " .. tostring(r.reasoning_effort))

            -- high: >= 16384
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                thinking = { type = "enabled", budget_tokens = 32000 },
            }, ctx)
            assert(r.reasoning_effort == "high", "high: " .. tostring(r.reasoning_effort))

            -- disabled: no reasoning_effort
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                thinking = { type = "disabled" },
            }, ctx)
            assert(r.reasoning_effort == nil, "disabled should be nil")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 19: image content block conversion
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "What is this?" },
                        { type = "image", source = {
                            type = "base64",
                            media_type = "image/jpeg",
                            data = "abc123"
                        }},
                    }
                }},
            }, ctx)

            -- Should be content array (multimodal)
            local msg = r.messages[1]
            assert(type(msg.content) == "table", "should be array")
            assert(msg.content[1].type == "text", "first is text")
            assert(msg.content[2].type == "image_url", "second is image_url")
            assert(msg.content[2].image_url.url == "data:image/jpeg;base64,abc123",
                   "url mismatch: " .. msg.content[2].image_url.url)
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 20: document (PDF) content block conversion
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Summarize this PDF" },
                        { type = "document", source = {
                            type = "base64",
                            media_type = "application/pdf",
                            data = "JVBER"
                        }},
                    }
                }},
            }, ctx)

            local msg = r.messages[1]
            assert(type(msg.content) == "table", "should be array")
            assert(msg.content[2].type == "image_url", "second is image_url")
            assert(msg.content[2].image_url.url == "data:application/pdf;base64,JVBER",
                   "url: " .. msg.content[2].image_url.url)
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 21: tool_result with array content (text + image)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "tool_result", tool_use_id = "call_1", content = {
                            { type = "text", text = "Screenshot taken" },
                            { type = "image", source = {
                                type = "base64", media_type = "image/png", data = "img"
                            }},
                        }},
                    }
                }},
            }, ctx)

            -- tool_result with image → content array with image_url
            local tool_msg = r.messages[1]
            assert(tool_msg.role == "tool", "role: " .. tool_msg.role)
            assert(tool_msg.tool_call_id == "call_1", "id mismatch")
            assert(type(tool_msg.content) == "table", "content should be array")
            assert(tool_msg.content[1].type == "text", "first text")
            assert(tool_msg.content[2].type == "image_url", "second image_url")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 22: empty tools array does NOT produce tools field (Bug 1 fix)
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {},
            }, ctx)

            assert(r.tools == nil, "empty tools should not produce tools field")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 23: response_format from output_config (json_schema)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_config = {
                    type = "json_schema",
                    json_schema = { name = "response", schema = { type = "object" } },
                },
            }, ctx)

            assert(r.response_format ~= nil, "response_format missing")
            assert(r.response_format.type == "json_schema", "type: " .. r.response_format.type)
            assert(r.response_format.json_schema.name == "response", "schema name")
            -- output_config should NOT leak
            assert(r.output_config == nil, "output_config leaked")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 24: response_format from output_format (json_object)
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_object" },
            }, ctx)

            assert(r.response_format ~= nil, "response_format missing")
            assert(r.response_format.type == "json_object", "type")
            assert(r.output_format == nil, "output_format leaked")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 25: cache_control stripped from tool definitions
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{
                    name = "search",
                    description = "Search the web",
                    input_schema = { type = "object" },
                    cache_control = { type = "ephemeral" },
                }},
            }, ctx)

            local encoded = core.json.encode(r.tools[1])
            assert(not encoded:find("cache_control"), "cache_control should be stripped: " .. encoded)
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 26: tool_use with empty input (no arguments)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "assistant",
                    content = {{
                        type = "tool_use",
                        id = "call_empty",
                        name = "get_time",
                        input = {},
                    }},
                }},
            }, ctx)

            local msg = r.messages[1]
            assert(msg.tool_calls ~= nil, "tool_calls missing")
            assert(msg.tool_calls[1]["function"].arguments == "{}",
                   "args: " .. msg.tool_calls[1]["function"].arguments)
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 27: header conversion (x-api-key → Authorization, remove anthropic-*)
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local headers = {
                ["x-api-key"] = "sk-ant-123",
                ["anthropic-version"] = "2023-06-01",
                ["anthropic-beta"] = "messages-2024",
                ["anthropic-custom-header"] = "should-be-removed",
                ["x-stainless-arch"] = "x86_64",
                ["x-stainless-os"] = "linux",
                ["content-type"] = "application/json",
            }

            converter.convert_headers(headers)

            assert(headers["authorization"] == "Bearer sk-ant-123",
                   "auth: " .. tostring(headers["authorization"]))
            assert(headers["x-api-key"] == nil, "x-api-key not removed")
            assert(headers["anthropic-version"] == nil, "anthropic-version not removed")
            assert(headers["anthropic-beta"] == nil, "anthropic-beta not removed")
            assert(headers["anthropic-custom-header"] == nil, "anthropic-custom-header not removed")
            assert(headers["x-stainless-arch"] == nil, "x-stainless-arch not removed")
            assert(headers["x-stainless-os"] == nil, "x-stainless-os not removed")
            assert(headers["content-type"] == "application/json", "content-type preserved")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 28: header conversion does not overwrite existing Authorization
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local headers = {
                ["x-api-key"] = "sk-ant-123",
                ["authorization"] = "Bearer existing-token",
            }

            converter.convert_headers(headers)

            assert(headers["authorization"] == "Bearer existing-token",
                   "should not overwrite existing auth")
            assert(headers["x-api-key"] == nil, "x-api-key should still be removed")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 29: billing header cch= stripping
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- cch at end
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                system = {{
                    type = "text",
                    text = "x-anthropic-billing-header:abc=123;cch=456",
                }},
                messages = {{ role = "user", content = "hi" }},
            }, ctx)
            local sys = r.messages[1]
            assert(sys.role == "system", "role")
            -- cch should be stripped
            assert(not sys.content:find("cch="), "cch not stripped: " .. sys.content)
            assert(sys.content:find("abc=123"), "abc preserved: " .. sys.content)

            -- no cch - unchanged
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                system = {{
                    type = "text",
                    text = "x-anthropic-billing-header:abc=123;def=789",
                }},
                messages = {{ role = "user", content = "hi" }},
            }, ctx)
            sys = r.messages[1]
            assert(sys.content:find("abc=123"), "no cch - abc: " .. sys.content)
            assert(sys.content:find("def=789"), "no cch - def: " .. sys.content)

            -- non billing header - left alone
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                system = {{ type = "text", text = "Just a normal system prompt" }},
                messages = {{ role = "user", content = "hi" }},
            }, ctx)
            sys = r.messages[1]
            assert(sys.content == "Just a normal system prompt", "normal prompt")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 30: streaming - reasoning_content delta → thinking block events
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- First chunk with reasoning
            local events = converter.convert_sse_events({
                type = "data",
                data = {
                    id = "chatcmpl-1",
                    model = "o1",
                    choices = {{ delta = { reasoning_content = "Let me " } }},
                },
            }, {}, state)

            assert(#events >= 2, "need message_start + content_block_start + delta")
            -- First event should be message_start
            local msg_start = core.json.decode(events[1].data)
            assert(msg_start.type == "message_start", "first is message_start")
            -- Second should be content_block_start (thinking)
            local block_start = core.json.decode(events[2].data)
            assert(block_start.type == "content_block_start", "second is block_start")
            assert(block_start.content_block.type == "thinking", "block type is thinking")
            -- Third should be thinking_delta
            local delta = core.json.decode(events[3].data)
            assert(delta.type == "content_block_delta", "third is delta")
            assert(delta.delta.type == "thinking_delta", "delta type: " .. delta.delta.type)
            assert(delta.delta.thinking == "Let me ", "thinking text")

            -- Continue reasoning
            events = converter.convert_sse_events({
                type = "data",
                data = {
                    choices = {{ delta = { reasoning_content = "think..." } }},
                },
            }, {}, state)
            assert(#events == 1, "just a delta")
            delta = core.json.decode(events[1].data)
            assert(delta.delta.thinking == "think...", "continued thinking")

            -- Transition to text
            events = converter.convert_sse_events({
                type = "data",
                data = {
                    choices = {{ delta = { content = "The answer" } }},
                },
            }, {}, state)
            -- Should close thinking block and start text block
            assert(#events >= 3, "stop + start + delta, got " .. #events)
            local stop = core.json.decode(events[1].data)
            assert(stop.type == "content_block_stop", "close thinking")
            local text_start = core.json.decode(events[2].data)
            assert(text_start.content_block.type == "text", "text block start")
            local text_delta = core.json.decode(events[3].data)
            assert(text_delta.delta.text == "The answer", "text content")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 31: streaming - null/empty finish_reason does NOT stop stream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- Init
            converter.convert_sse_events({
                type = "data",
                data = { id = "x", model = "m", choices = {{ delta = { content = "hi" } }} },
            }, {}, state)

            -- Chunk with null finish_reason (like cjson.null being nil after decode)
            local events = converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = { content = " there" }, finish_reason = nil }} },
            }, {}, state)
            -- Should NOT trigger message_stop
            assert(not state.is_done, "nil finish_reason should not stop")

            -- Chunk with empty string finish_reason
            events = converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = { content = "!" }, finish_reason = "" }} },
            }, {}, state)
            assert(not state.is_done, "empty finish_reason should not stop")

            -- Chunk with "null" string
            events = converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = {}, finish_reason = "null" }} },
            }, {}, state)
            assert(not state.is_done, "\"null\" string should not stop")

            -- Real finish_reason should stop
            events = converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = {}, finish_reason = "stop" }} },
            }, {}, state)
            assert(state.is_done, "\"stop\" should stop the stream")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 32: streaming - usage deferred to final chunk after finish_reason
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- Init + text
            converter.convert_sse_events({
                type = "data",
                data = { id = "x", model = "m", choices = {{ delta = { content = "hi" } }} },
            }, {}, state)

            -- finish_reason without usage (deferred)
            converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = {}, finish_reason = "stop" }} },
            }, {}, state)
            assert(state.is_done, "should be done")
            assert(state.pending_stop, "should have pending stop")

            -- Usage arrives in trailing chunk
            local events = converter.convert_sse_events({
                type = "data",
                data = {
                    choices = {},
                    usage = {
                        prompt_tokens = 100,
                        completion_tokens = 50,
                        prompt_tokens_details = { cached_tokens = 20 },
                    },
                },
            }, {}, state)

            -- Should now emit message_delta with usage + message_stop
            assert(#events == 2, "expect 2 events, got " .. #events)
            local msg_delta = core.json.decode(events[1].data)
            assert(msg_delta.type == "message_delta", "first is message_delta")
            assert(msg_delta.usage.input_tokens == 80, "input: " .. msg_delta.usage.input_tokens)
            assert(msg_delta.usage.output_tokens == 50, "output: " .. msg_delta.usage.output_tokens)
            assert(msg_delta.usage.cache_read_input_tokens == 20,
                   "cached: " .. tostring(msg_delta.usage.cache_read_input_tokens))
            local msg_stop = core.json.decode(events[2].data)
            assert(msg_stop.type == "message_stop", "second is message_stop")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 33: streaming - dynamic content_block index (thinking → text → tool)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- Reasoning → index 0
            converter.convert_sse_events({
                type = "data",
                data = { id = "x", model = "m",
                         choices = {{ delta = { reasoning_content = "hmm" } }} },
            }, {}, state)
            assert(state.next_content_index == 1, "after thinking: idx=" .. state.next_content_index)

            -- Text → index 1
            converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = { content = "answer" } }} },
            }, {}, state)
            assert(state.next_content_index == 2, "after text: idx=" .. state.next_content_index)

            -- Tool call → index 2
            converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = {
                    tool_calls = {{ index = 0, id = "call_1",
                                    ["function"] = { name = "f", arguments = "" } }}
                } }} },
            }, {}, state)
            assert(state.next_content_index == 3, "after tool: idx=" .. state.next_content_index)

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 34: streaming - duplicate chunks after message_stop are ignored
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- Init + finish
            converter.convert_sse_events({
                type = "data",
                data = { id = "x", model = "m", choices = {{ delta = { content = "hi" } }} },
            }, {}, state)
            converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = {}, finish_reason = "stop" }},
                         usage = { prompt_tokens = 10, completion_tokens = 5 } },
            }, {}, state)

            -- Flush pending
            local events = converter.convert_sse_events({
                type = "done",
            }, {}, state)
            assert(#events == 2, "flush: " .. #events)

            -- Another "done" after message_stop → ignored
            events = converter.convert_sse_events({
                type = "done",
            }, {}, state)
            assert(events == nil, "should be nil after stop")

            -- Another data chunk after done → ignored
            events = converter.convert_sse_events({
                type = "data",
                data = { choices = {{ delta = { content = "extra" } }} },
            }, {}, state)
            assert(#events == 0, "should produce no events: " .. #events)

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 35: multiple tool_results in single user message → separate tool messages
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "tool_result", tool_use_id = "call_1", content = "result 1" },
                        { type = "tool_result", tool_use_id = "call_2", content = "result 2" },
                    }
                }},
            }, ctx)

            -- Should produce 2 separate tool messages
            assert(#r.messages == 2, "expected 2 messages, got " .. #r.messages)
            assert(r.messages[1].role == "tool", "msg 1 role")
            assert(r.messages[1].tool_call_id == "call_1", "msg 1 id")
            assert(r.messages[1].content == "result 1", "msg 1 content")
            assert(r.messages[2].role == "tool", "msg 2 role")
            assert(r.messages[2].tool_call_id == "call_2", "msg 2 id")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 36: text alongside tool_results → text message + tool messages
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Here are the results:" },
                        { type = "tool_result", tool_use_id = "call_1", content = "done" },
                    }
                }},
            }, ctx)

            -- text message first, then tool message
            assert(#r.messages == 2, "expected 2 messages, got " .. #r.messages)
            assert(r.messages[1].role == "user", "msg 1 role")
            assert(r.messages[1].content == "Here are the results:", "msg 1 text")
            assert(r.messages[2].role == "tool", "msg 2 role")
            assert(r.messages[2].tool_call_id == "call_1", "msg 2 id")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 37: mixed text + tool_use in assistant message
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "assistant",
                    content = {
                        { type = "text", text = "Let me search for that." },
                        { type = "tool_use", id = "call_1", name = "search",
                          input = { query = "test" } },
                    }
                }},
            }, ctx)

            local msg = r.messages[1]
            assert(msg.role == "assistant", "role")
            assert(msg.content == "Let me search for that.", "text content")
            assert(msg.tool_calls ~= nil, "tool_calls present")
            assert(#msg.tool_calls == 1, "one tool call")
            assert(msg.tool_calls[1]["function"].name == "search", "tool name")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 38: stop_sequences → stop conversion
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                stop_sequences = { "END", "STOP" },
            }, ctx)

            assert(type(r.stop) == "table", "stop should be table")
            assert(r.stop[1] == "END", "first stop")
            assert(r.stop[2] == "STOP", "second stop")
            assert(r.stop_sequences == nil, "stop_sequences should not leak")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 39: image with URL source type
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- Valid URL source
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Describe this" },
                        { type = "image", source = {
                            type = "url",
                            url = "https://example.com/image.png"
                        }},
                    }
                }},
            }, ctx)

            local msg = r.messages[1]
            assert(type(msg.content) == "table", "should be array")
            assert(msg.content[2].type == "image_url", "type")
            assert(msg.content[2].image_url.url == "https://example.com/image.png", "url")

            -- Empty URL source - should be skipped
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Describe this" },
                        { type = "image", source = { type = "url", url = "" }},
                    }
                }},
            }, ctx)
            msg = r.messages[1]
            -- Only text should remain (image skipped)
            assert(msg.content == "Describe this", "empty url skipped: " .. tostring(msg.content))

            -- nil URL source - should be skipped
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Test" },
                        { type = "image", source = { type = "url" }},
                    }
                }},
            }, ctx)
            msg = r.messages[1]
            assert(msg.content == "Test", "nil url skipped: " .. tostring(msg.content))

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 40: stream=true adds stream_options.include_usage
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100, stream = true,
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)

            assert(r.stream == true, "stream")
            assert(type(r.stream_options) == "table", "stream_options exists")
            assert(r.stream_options.include_usage == true, "include_usage")

            -- Non-streaming should not have stream_options
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100, stream = false,
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)
            assert(r2.stream_options == nil, "no stream_options when not streaming")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 41: cache_control stripped from system, messages, and tools
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                system = {
                    { type = "text", text = "System prompt", cache_control = { type = "ephemeral" } },
                },
                messages = {{
                    role = "user",
                    content = {
                        { type = "text", text = "Hello", cache_control = { type = "ephemeral" } },
                    }
                }},
                tools = {{
                    name = "my_tool",
                    description = "A tool",
                    input_schema = { type = "object" },
                    cache_control = { type = "ephemeral" },
                }},
            }, ctx)

            -- System: should be plain string, no cache_control
            assert(r.messages[1].role == "system", "system role")
            assert(type(r.messages[1].content) == "string", "system is string: " .. type(r.messages[1].content))

            -- User message: should be flattened string, no cache_control
            assert(r.messages[2].content == "Hello", "user content flattened")

            -- Tool: no cache_control field
            local encoded = core.json.encode(r.tools[1])
            assert(not encoded:find("cache_control"), "no cache_control in tool: " .. encoded)

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 42: metadata.user_id → user field
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                metadata = { user_id = "user-123" },
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)

            assert(r.user == "user-123", "user field: " .. tostring(r.user))

            -- No metadata: no user field
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)
            assert(r2.user == nil, "no user when no metadata")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 43: Anthropic built-in tools are silently skipped
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {
                    { type = "computer_20241022", name = "computer", display_width_px = 1024 },
                    { type = "bash_20250124", name = "bash" },
                    { type = "text_editor_20250124", name = "text_editor" },
                    { name = "normal_tool", description = "A normal tool", input_schema = { type = "object" } },
                },
            }, ctx)

            -- Only the normal tool should survive
            assert(#r.tools == 1, "expected 1 tool, got " .. #r.tools)
            assert(r.tools[1]["function"].name == "normal_tool", "normal tool name")

            -- All built-in tools: should produce no tools
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {
                    { type = "web_search_20260209", name = "web_search" },
                    { type = "code_execution_20250522", name = "code_exec" },
                },
            }, ctx)
            assert(r2.tools == nil, "no tools when all are built-in")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 44: ping SSE event pass-through
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local state = { is_first = true }

            local events = converter.convert_sse_events({ type = "ping" }, {}, state)

            assert(type(events) == "table", "events is table")
            assert(#events == 1, "one event")
            local decoded = core.json.decode(events[1].data)
            assert(decoded.type == "ping", "ping type: " .. tostring(decoded.type))
            assert(events[1].type == "ping", "event type: " .. events[1].type)

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 45: tool name truncation and mapping
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = { llm_model = "gpt-4o" } }

            -- Tool name with 70 chars (exceeds 64 limit)
            local long_name = string.rep("a", 70)
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {{
                    name = long_name,
                    description = "Long tool",
                    input_schema = { type = "object" },
                }},
            }, ctx)

            -- Should be truncated to 64 chars
            local oai_name = r.tools[1]["function"].name
            assert(#oai_name == 64, "truncated to 64: " .. #oai_name)

            -- Mapping stored in ctx
            assert(ctx.anthropic_tool_name_map ~= nil, "map exists")
            assert(ctx.anthropic_tool_name_map[oai_name] == long_name, "map correct")

            -- Response conversion restores original name
            local res = converter.convert_response({
                id = "msg_1",
                choices = {{ message = { tool_calls = {{
                    id = "call_1",
                    type = "function",
                    ["function"] = { name = oai_name, arguments = "{}" },
                }}}, finish_reason = "tool_calls" }},
                usage = { prompt_tokens = 10, completion_tokens = 5 },
            }, ctx)
            assert(res.content[1].name == long_name, "restored name: " .. res.content[1].name)

            -- Tool with invalid chars
            local ctx2 = { var = { llm_model = "gpt-4o" } }
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {{
                    name = "my tool.with spaces!",
                    description = "Invalid chars",
                    input_schema = { type = "object" },
                }},
            }, ctx2)
            local sanitized = r2.tools[1]["function"].name
            -- Should only contain valid chars
            assert(not sanitized:find("[^a-zA-Z0-9_%-]"), "valid chars only: " .. sanitized)

            -- Collision disambiguation: two tools that sanitize to the same name
            local ctx3 = { var = { llm_model = "gpt-4o" } }
            local r3 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {
                    { name = "my tool!foo", description = "A", input_schema = { type = "object" } },
                    { name = "my tool@foo", description = "B", input_schema = { type = "object" } },
                },
            }, ctx3)
            local n1 = r3.tools[1]["function"].name
            local n2 = r3.tools[2]["function"].name
            assert(n1 ~= n2, "no collision: " .. n1 .. " vs " .. n2)
            -- Both map back to different original names
            assert(ctx3.anthropic_tool_name_map[n1] == "my tool!foo", "map1: " .. tostring(ctx3.anthropic_tool_name_map[n1]))
            assert(ctx3.anthropic_tool_name_map[n2] == "my tool@foo", "map2: " .. tostring(ctx3.anthropic_tool_name_map[n2]))

            -- Collision with max-length names: suffix must not exceed 64 chars
            local ctx3b = { var = { llm_model = "gpt-4o" } }
            local long64_a = string.rep("x", 60) .. "!aaa"
            local long64_b = string.rep("x", 60) .. "@aaa"
            local r3b = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {
                    { name = long64_a, description = "A", input_schema = { type = "object" } },
                    { name = long64_b, description = "B", input_schema = { type = "object" } },
                },
            }, ctx3b)
            local nb1 = r3b.tools[1]["function"].name
            local nb2 = r3b.tools[2]["function"].name
            assert(nb1 ~= nb2, "long collision distinct: " .. nb1 .. " vs " .. nb2)
            assert(#nb1 <= 64, "name1 <= 64: " .. #nb1)
            assert(#nb2 <= 64, "name2 <= 64: " .. #nb2)

            -- tool_choice name is sanitized consistently with tool definitions
            local ctx4 = { var = { llm_model = "gpt-4o" } }
            local r4 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {{
                    name = long_name,
                    description = "Long tool",
                    input_schema = { type = "object" },
                }},
                tool_choice = { type = "tool", name = long_name },
            }, ctx4)
            local tc_name = r4.tool_choice["function"].name
            local tool_fn_name = r4.tools[1]["function"].name
            assert(tc_name == tool_fn_name, "tool_choice matches tool: " .. tc_name .. " vs " .. tool_fn_name)

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 46: service_tier passthrough
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                service_tier = "auto",
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)

            assert(r.service_tier == "auto", "service_tier: " .. tostring(r.service_tier))

            -- No service_tier: not present
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
            }, ctx)
            assert(r2.service_tier == nil, "no service_tier")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]
