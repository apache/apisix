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
  - ai-proxy
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
            if result.reasoning_effort ~= "high" then
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

            local function effort_of(thinking)
                local r = converter.convert_request({
                    model = "m", max_tokens = 100,
                    messages = {{ role = "user", content = "hi" }},
                    thinking = thinking,
                }, ctx)
                return r.reasoning_effort
            end

            -- budget buckets: < 1024 minimal, < 2048 low, < 4096 medium, else high
            local cases = {
                { 0, "minimal" }, { 1023, "minimal" },
                { 1024, "low" }, { 2047, "low" },
                { 2048, "medium" }, { 4095, "medium" },
                { 4096, "high" }, { 32000, "high" },
            }
            for _, c in ipairs(cases) do
                local got = effort_of({ type = "enabled", budget_tokens = c[1] })
                assert(got == c[2], c[1] .. " => " .. tostring(got))
            end

            -- enabled without budget_tokens is treated as a zero budget
            assert(effort_of({ type = "enabled" }) == "minimal", "no budget")

            -- disabled: no reasoning_effort
            assert(effort_of({ type = "disabled" }) == nil, "disabled should be nil")

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



=== TEST 23: response_format from output_config.format (json_schema)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local schema = {
                type = "object",
                properties = { a = { type = "string" }, b = { type = "string" } },
                required = { "a" },
            }
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_config = {
                    effort = "high",
                    format = { type = "json_schema", schema = schema },
                },
            }, ctx)

            assert(r.response_format ~= nil, "response_format missing")
            assert(r.response_format.type == "json_schema", "type: " .. r.response_format.type)
            assert(r.response_format.json_schema.name == "structured_output", "schema name")
            assert(r.response_format.json_schema.strict == true, "strict")

            -- strict mode: additionalProperties false, every property required
            local out = r.response_format.json_schema.schema
            assert(out.additionalProperties == false, "additionalProperties false")
            assert(#out.required == 2, "all properties required, got " .. #out.required)

            -- the client's schema must not be mutated in place
            assert(schema.additionalProperties == nil, "input schema mutated")
            assert(#schema.required == 1, "input required mutated")

            -- output_config should NOT leak
            assert(r.output_config == nil, "output_config leaked")

            -- an object with no properties still needs `required` to be a JSON
            -- array, and every nested sub-schema has to be normalized too
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_schema", schema = {
                    type = "object",
                    properties = {
                        empty = { type = "object", properties = {} },
                        list = { type = "array", items = {
                            type = "object", properties = { k = { type = "string" } },
                        }},
                        choice = { anyOf = {
                            { type = "object", properties = { m = { type = "string" } } },
                        }},
                        ref = { ["$ref"] = "#/$defs/Inner" },
                    },
                    ["$defs"] = {
                        Inner = { type = "object", properties = { z = { type = "boolean" } } },
                    },
                }},
            }, ctx)
            local out2 = r2.response_format.json_schema.schema
            local encoded = core.json.encode(out2)
            assert(encoded:find('"required":%[%]'), "empty required must encode as []: " .. encoded)
            assert(out2.properties.empty.additionalProperties == false, "nested empty object")
            assert(out2.properties.list.items.additionalProperties == false, "array items")
            assert(out2.properties.choice.anyOf[1].additionalProperties == false, "anyOf branch")
            assert(out2["$defs"].Inner.additionalProperties == false, "$defs entry")
            assert(out2["$defs"].Inner.required[1] == "z", "$defs required")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 24: only json_schema output formats become response_format
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- `json_object` is not an Anthropic output format, so nothing is emitted
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_object" },
            }, ctx)
            assert(r.response_format == nil, "json_object should not map to response_format")
            assert(r.output_format == nil, "output_format leaked")

            -- json_schema without a schema is incomplete, so nothing is emitted either
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_schema" },
            }, ctx)
            assert(r.response_format == nil, "schema-less json_schema")

            -- an empty schema carries nothing to enforce
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_schema", schema = {} },
            }, ctx)
            assert(r.response_format == nil, "empty json_schema")

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



=== TEST 36: text alongside tool_results → tool messages first, then text message
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

            -- tool message first, then text message
            assert(#r.messages == 2, "expected 2 messages, got " .. #r.messages)
            assert(r.messages[1].role == "tool", "msg 1 role")
            assert(r.messages[1].tool_call_id == "call_1", "msg 1 id")
            assert(r.messages[2].role == "user", "msg 2 role")
            assert(r.messages[2].content[1].text == "Here are the results:", "msg 2 text")
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
            assert(#msg.content == 1, "empty url skipped: " .. #msg.content)
            assert(msg.content[1].text == "Describe this", "text kept")

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
            assert(#msg.content == 1, "nil url skipped: " .. #msg.content)
            assert(msg.content[1].text == "Test", "text kept")

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

            -- User message: content array without cache_control
            assert(r.messages[2].content[1].text == "Hello", "user text kept")
            assert(r.messages[2].content[1].cache_control == nil, "no cache_control in message")

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

            -- A name that already fits is forwarded untouched, with no mapping
            local ctx0 = { var = {} }
            local r0 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "Hi" }},
                tools = {{ name = string.rep("a", 64), input_schema = { type = "object" } }},
            }, ctx0)
            assert(r0.tools[1]["function"].name == string.rep("a", 64), "64 chars is fine")
            assert(ctx0.anthropic_tool_name_map == nil, "no map when nothing is renamed")

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

            -- <55-char prefix>_<8 hex chars of sha256(name)>, byte-for-byte what
            -- LiteLLM's truncate_tool_name() produces for the same input
            local oai_name = r.tools[1]["function"].name
            assert(oai_name == string.rep("a", 55) .. "_6bd5e503", "hashed: " .. oai_name)
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



=== TEST 47: set route for native Anthropic protocol built-in var tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key"
                                }
                            },
                            "options": {
                                "model": "claude-3-5-sonnet-20241022"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
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



=== TEST 48: Anthropic streaming accumulates total_tokens from split message_start and message_delta events
--- request
POST /v1/messages
{"messages":[{"role":"user","content":"Hello"}],"model":"claude-3-5-sonnet-20241022","max_tokens":1024,"stream":true}
--- more_headers
X-AI-Fixture: anthropic/messages-streaming.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" claude-3-5-sonnet-20241022 claude-3-5-sonnet-20241022 [\d.]+ 10 8 18 true false 0 /



=== TEST 49: Anthropic streaming detects tool_use in content_block_start as tool call
--- request
POST /v1/messages
{"messages":[{"role":"user","content":"What is the weather?"}],"model":"claude-3-5-sonnet-20241022","max_tokens":1024,"stream":true}
--- more_headers
X-AI-Fixture: anthropic/messages-streaming-with-tool-use.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" claude-3-5-sonnet-20241022 claude-3-5-sonnet-20241022 [\d.]+ 20 5 25 true true 0 /



=== TEST 50: Anthropic non-streaming writes cache tokens to access log
--- request
POST /v1/messages
{"messages":[{"role":"user","content":"Hello"}],"model":"claude-3-5-sonnet-20241022","max_tokens":1024}
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" claude-3-5-sonnet-20241022 claude-3-5-sonnet-20241022 [\d.]+ 50 30 80 false false 0 \S* 200 100 0/



=== TEST 51: Anthropic streaming writes cache tokens to access log
--- request
POST /v1/messages
{"messages":[{"role":"user","content":"Hello"}],"model":"claude-3-5-sonnet-20241022","max_tokens":1024,"stream":true}
--- more_headers
X-AI-Fixture: anthropic/messages-streaming-with-cache.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" claude-3-5-sonnet-20241022 claude-3-5-sonnet-20241022 [\d.]+ 50 30 80 true false 0 \S* 200 100 0/



=== TEST 52: tool_choice is dropped when no tools are forwarded to upstream
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- tool_choice set but no tools field at all
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tool_choice = { type = "auto" },
            }, ctx)
            assert(r.tools == nil, "tools should be nil")
            assert(r.tool_choice == nil, "tool_choice must be dropped without tools")

            -- tools present but all are Anthropic built-ins (dropped)
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ type = "web_search", name = "web_search" }},
                tool_choice = { type = "any", disable_parallel_tool_use = true },
            }, ctx)
            assert(r.tools == nil, "all built-in tools dropped, tools nil")
            assert(r.tool_choice == nil, "tool_choice must be dropped when tools empty")
            assert(r.parallel_tool_calls == nil, "parallel_tool_calls must be dropped too")

            -- sanity: tool_choice preserved when a real tool remains
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "f", input_schema = {} }},
                tool_choice = { type = "auto" },
            }, ctx)
            assert(r.tool_choice == "auto", "tool_choice kept with a real tool")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 53: streaming - done after message_start without content block emits message_stop
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local state = { is_first = true }

            -- First chunk opens the message (message_start) but no content block
            local events = converter.convert_sse_events({
                type = "data",
                data = { id = "x", model = "m", choices = {{ delta = { role = "assistant" } }} },
            }, {}, state)
            assert(#events >= 1, "expected message_start")
            assert(core.json.decode(events[1].data).type == "message_start", "first is message_start")
            assert(state.current_open_block == nil, "no content block opened")

            -- Upstream ends the stream with [DONE] and no finish_reason chunk
            events = converter.convert_sse_events({ type = "done" }, {}, state)
            assert(events ~= nil, "done must not return nil after message_start")
            local saw_stop = false
            for _, e in ipairs(events) do
                if core.json.decode(e.data).type == "message_stop" then
                    saw_stop = true
                end
            end
            assert(saw_stop, "message_stop must be emitted to avoid hanging the client")
            assert(state.is_done, "stream marked done")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 54: malformed tool_call arguments fall back to empty input instead of aborting
An OpenAI-compatible upstream may emit tool_call arguments that are not valid
JSON (or not a JSON object). The converter must not abort the whole response --
which would also drop already-collected text/thinking content -- but fall back
to an empty input object and log a warning.
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = { llm_model = "gpt-4o" } }

            local res, err = converter.convert_response({
                id = "msg_1",
                choices = {{
                    message = {
                        content = "partial answer",
                        tool_calls = {{
                            id = "call_1",
                            type = "function",
                            ["function"] = { name = "do_it", arguments = "{not valid json" },
                        }},
                    },
                    finish_reason = "tool_calls",
                }},
                usage = { prompt_tokens = 10, completion_tokens = 5 },
            }, ctx)

            assert(res ~= nil, "conversion must not abort: " .. tostring(err))

            local has_text, has_tool = false, false
            for _, c in ipairs(res.content) do
                if c.type == "text" and c.text == "partial answer" then
                    has_text = true
                end
                if c.type == "tool_use" then
                    has_tool = true
                    assert(type(c.input) == "table", "input is an object")
                    assert(next(c.input) == nil, "input is an empty object")
                    assert(c.name == "do_it", "tool name preserved")
                end
            end
            assert(has_text, "already-collected text content preserved")
            assert(has_tool, "tool_use block still emitted")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- error_log
failed to decode tool_call arguments



=== TEST 55: tool_call arguments that decode to non-object fall back to empty input
Valid JSON that is not an object (number, string, boolean) should also trigger
the empty-object fallback and log "not a JSON object".
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = { llm_model = "gpt-4o" } }

            local res, err = converter.convert_response({
                id = "msg_1",
                choices = {{
                    message = {
                        content = "answer",
                        tool_calls = {{
                            id = "call_1",
                            type = "function",
                            ["function"] = { name = "do_it", arguments = "123" },
                        }},
                    },
                    finish_reason = "tool_calls",
                }},
                usage = { prompt_tokens = 10, completion_tokens = 5 },
            }, ctx)

            assert(res ~= nil, "conversion must not abort: " .. tostring(err))

            local has_text, has_tool = false, false
            for _, c in ipairs(res.content) do
                if c.type == "text" and c.text == "answer" then
                    has_text = true
                end
                if c.type == "tool_use" then
                    has_tool = true
                    assert(type(c.input) == "table", "input is an object")
                    assert(next(c.input) == nil, "input is an empty object")
                end
            end
            assert(has_text, "already-collected text content preserved")
            assert(has_tool, "tool_use block emitted")

            ngx.say("OK")
        }
    }
--- response_body
OK
--- error_log
not a JSON object



=== TEST 56: tool_results precede the trailing text message (parallel tool_calls)
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            -- assistant emits 2 parallel tool_use blocks, the next user message
            -- carries both tool_results plus extra text (what Claude Code sends
            -- when a system-reminder or a queued prompt rides along).
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {
                    { role = "user", content = "start" },
                    { role = "assistant", content = {
                        { type = "tool_use", id = "call_a", name = "get_a", input = {} },
                        { type = "tool_use", id = "call_b", name = "get_b", input = {} },
                    }},
                    { role = "user", content = {
                        { type = "tool_result", tool_use_id = "call_a", content = "a" },
                        { type = "tool_result", tool_use_id = "call_b", content = "b" },
                        { type = "text", text = "also explain briefly" },
                    }},
                },
            }, ctx)

            -- every tool message must immediately follow the assistant tool_calls
            assert(#r.messages == 5, "expected 5 messages, got " .. #r.messages)
            assert(r.messages[2].role == "assistant", "assistant")
            assert(#r.messages[2].tool_calls == 2, "2 tool_calls")
            assert(r.messages[3].role == "tool", "msg 3 role: " .. r.messages[3].role)
            assert(r.messages[3].tool_call_id == "call_a", "msg 3 id")
            assert(r.messages[4].role == "tool", "msg 4 role: " .. r.messages[4].role)
            assert(r.messages[4].tool_call_id == "call_b", "msg 4 id")
            assert(r.messages[5].role == "user", "msg 5 role")
            assert(r.messages[5].content[1].text == "also explain briefly", "msg 5 text")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 57: media alongside tool_results is preserved after the tool messages
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
                        { type = "tool_result", tool_use_id = "call_1", content = "done" },
                        { type = "text", text = "look at this" },
                        { type = "image", source = {
                            type = "base64", media_type = "image/png", data = "img",
                        }},
                    }
                }},
            }, ctx)

            assert(#r.messages == 2, "expected 2 messages, got " .. #r.messages)
            assert(r.messages[1].role == "tool", "tool message first")
            local content = r.messages[2].content
            assert(r.messages[2].role == "user", "user message second")
            assert(type(content) == "table", "multimodal content kept as array")
            assert(content[1].type == "text", "text part")
            assert(content[2].type == "image_url", "image part kept")
            assert(content[2].image_url.url == "data:image/png;base64,img", "image url")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 58: tool_result only (no extra content) emits no trailing message
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
                        { type = "tool_result", tool_use_id = "call_1", content = "done" },
                    }
                }},
            }, ctx)

            assert(#r.messages == 1, "expected 1 message, got " .. #r.messages)
            assert(r.messages[1].role == "tool", "tool message only")

            -- an empty text block is still a block: it becomes a trailing message
            r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{
                    role = "user",
                    content = {
                        { type = "tool_result", tool_use_id = "call_1", content = "done" },
                        { type = "text", text = "" },
                    }
                }},
            }, ctx)
            assert(#r.messages == 2, "expected 2 messages, got " .. #r.messages)
            assert(r.messages[2].content[1].text == "", "empty text block kept")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 59: adaptive thinking → reasoning_effort from output_config.effort
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")

            local function effort_of(thinking, output_config)
                local r = converter.convert_request({
                    model = "m", max_tokens = 100,
                    messages = {{ role = "user", content = "hi" }},
                    thinking = thinking,
                    output_config = output_config,
                }, { var = {} })
                return r.reasoning_effort
            end

            -- output_config.effort is forwarded verbatim: Chat Completions takes
            -- the same labels (none/minimal/low/medium/high/xhigh)
            local adaptive = { type = "adaptive" }
            assert(effort_of(adaptive, { effort = "low" }) == "low", "low")
            assert(effort_of(adaptive, { effort = "high" }) == "high", "high")
            assert(effort_of(adaptive, { effort = "xhigh" }) == "xhigh", "xhigh")
            assert(effort_of(adaptive, { effort = "max" }) == "max", "max")
            -- adaptive without an explicit effort falls back to medium
            assert(effort_of(adaptive, nil) == "medium", "default medium")
            assert(effort_of(adaptive, {}) == "medium", "empty output_config -> medium")
            assert(effort_of(adaptive, { effort = "" }) == "medium", "empty effort -> medium")
            -- output_config.effort alone does not enable reasoning
            assert(effort_of(nil, { effort = "high" }) == nil, "no thinking, no effort")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 60: response_format from output_format (json_schema, beta shape)
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local schema = { type = "object", additionalProperties = false }
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_schema", schema = schema },
            }, ctx)

            assert(r.response_format.type == "json_schema", "type")
            assert(r.response_format.json_schema.strict == true, "strict")
            assert(r.response_format.json_schema.schema.type == "object", "schema forwarded")
            assert(r.output_format == nil, "output_format leaked")

            -- an absent/empty output_format falls back to output_config.format
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_config = { format = { type = "json_schema", schema = { type = "object" } } },
            }, { var = {} })
            assert(r2.response_format ~= nil, "output_config.format used")
            assert(r2.response_format.json_schema.strict == true, "strict")

            -- the top-level output_format wins when both carry a schema
            local r3 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                output_format = { type = "json_schema", schema = { type = "object", title = "beta" } },
                output_config = { format = { type = "json_schema", schema = { type = "object", title = "ga" } } },
            }, { var = {} })
            assert(r3.response_format.json_schema.schema.title == "beta", "output_format wins")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 61: tool_use in history uses the same sanitized name as the tool definition
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = { llm_model = "gpt-4o" } }

            local long_name = string.rep("a", 70)
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                tools = {
                    { name = long_name, description = "Long", input_schema = { type = "object" } },
                    { name = "my tool!x", description = "Invalid chars", input_schema = { type = "object" } },
                },
                messages = {
                    { role = "user", content = "hi" },
                    { role = "assistant", content = {
                        { type = "tool_use", id = "call_1", name = long_name, input = {} },
                        { type = "tool_use", id = "call_2", name = "my tool!x", input = {} },
                    }},
                    { role = "user", content = {
                        { type = "tool_result", tool_use_id = "call_1", content = "ok" },
                        { type = "tool_result", tool_use_id = "call_2", content = "ok" },
                    }},
                },
            }, ctx)

            local declared_1 = r.tools[1]["function"].name
            local declared_2 = r.tools[2]["function"].name
            local called_1 = r.messages[2].tool_calls[1]["function"].name
            local called_2 = r.messages[2].tool_calls[2]["function"].name
            assert(called_1 == declared_1, "call 1: " .. called_1 .. " vs " .. declared_1)
            assert(called_2 == declared_2, "call 2: " .. called_2 .. " vs " .. declared_2)
            assert(not called_2:find("[^a-zA-Z0-9_%-]"), "valid chars: " .. called_2)

            -- a tool_use whose definition is absent still gets a valid name and
            -- is restored on the response
            local ctx2 = { var = { llm_model = "gpt-4o" } }
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "assistant", content = {
                    { type = "tool_use", id = "call_1", name = "orphan tool!", input = {} },
                }}},
            }, ctx2)
            local orphan = r2.messages[1].tool_calls[1]["function"].name
            assert(not orphan:find("[^a-zA-Z0-9_%-]"), "orphan sanitized: " .. orphan)
            assert(ctx2.anthropic_tool_name_map[orphan] == "orphan tool!", "orphan mapped")

            local res = converter.convert_response({
                id = "msg_1",
                choices = {{ message = { tool_calls = {{
                    id = "call_1", type = "function",
                    ["function"] = { name = orphan, arguments = "{}" },
                }}}, finish_reason = "tool_calls" }},
                usage = { prompt_tokens = 10, completion_tokens = 5 },
            }, ctx2)
            assert(res.content[1].name == "orphan tool!", "restored: " .. res.content[1].name)
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 62: a rewritten tool name does not take a name another tool already owns
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = { llm_model = "gpt-4o" } }

            -- "get weather" sanitizes to "get_weather", which is also a literal
            -- tool name here; the tool that owns it verbatim must keep it
            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                tools = {
                    { name = "get weather", description = "A", input_schema = { type = "object" } },
                    { name = "get_weather", description = "B", input_schema = { type = "object" } },
                },
                messages = {
                    { role = "user", content = "hi" },
                    { role = "assistant", content = {
                        { type = "tool_use", id = "c1", name = "get weather", input = {} },
                        { type = "tool_use", id = "c2", name = "get_weather", input = {} },
                    }},
                },
            }, ctx)

            local n1 = r.tools[1]["function"].name
            local n2 = r.tools[2]["function"].name
            assert(n1 ~= n2, "tool names must be unique: " .. n1 .. " vs " .. n2)
            assert(n2 == "get_weather", "valid name kept: " .. n2)
            -- history tool_use follows the same mapping
            assert(r.messages[2].tool_calls[1]["function"].name == n1, "call 1")
            assert(r.messages[2].tool_calls[2]["function"].name == n2, "call 2")

            -- each openai name restores to the right original
            local function restore(oai_name)
                local res = converter.convert_response({
                    id = "msg_1",
                    choices = {{ message = { tool_calls = {{
                        id = "c", type = "function",
                        ["function"] = { name = oai_name, arguments = "{}" },
                    }}}, finish_reason = "tool_calls" }},
                    usage = { prompt_tokens = 1, completion_tokens = 1 },
                }, ctx)
                return res.content[1].name
            end
            assert(restore(n1) == "get weather", "restore n1: " .. restore(n1))
            assert(restore(n2) == "get_weather", "restore n2: " .. restore(n2))

            -- a 70-char name truncates onto a 64-char name owned by another tool
            local ctx2 = { var = { llm_model = "gpt-4o" } }
            local name64 = string.rep("a", 64)
            local name70 = string.rep("a", 70)
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                tools = {
                    { name = name64, description = "A", input_schema = { type = "object" } },
                    { name = name70, description = "B", input_schema = { type = "object" } },
                },
                messages = {{ role = "user", content = "hi" }},
            }, ctx2)
            local m1 = r2.tools[1]["function"].name
            local m2 = r2.tools[2]["function"].name
            assert(m1 == name64, "64-char name kept as is")
            assert(m2 ~= m1, "truncated name must not collide: " .. m2)
            assert(#m2 <= 64, "still within the limit: " .. #m2)
            assert(ctx2.anthropic_tool_name_map[m2] == name70, "truncated name maps back")
            assert(ctx2.anthropic_tool_name_map[m1] == nil, "untouched name needs no mapping")

            -- two long names that share their first 64 chars: the hash suffix is
            -- what keeps them apart
            local ctx3 = { var = { llm_model = "gpt-4o" } }
            local prefix = "mcp__server__" .. string.rep("a", 55)
            local r3 = converter.convert_request({
                model = "m", max_tokens = 100,
                tools = {
                    { name = prefix .. "_one", input_schema = { type = "object" } },
                    { name = prefix .. "_two", input_schema = { type = "object" } },
                },
                messages = {{ role = "user", content = "hi" }},
            }, ctx3)
            local p1 = r3.tools[1]["function"].name
            local p2 = r3.tools[2]["function"].name
            assert(p1 ~= p2, "shared prefix must not collide: " .. p1)
            assert(ctx3.anthropic_tool_name_map[p1] == prefix .. "_one", "prefix map 1")
            assert(ctx3.anthropic_tool_name_map[p2] == prefix .. "_two", "prefix map 2")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 63: content block shaping depends on the role
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {
                    -- a user turn keeps its blocks as an array, even a single one
                    { role = "user", content = {{ type = "text", text = "a" }} },
                    -- an assistant turn only carries text, so it becomes a string
                    { role = "assistant", content = {
                        { type = "text", text = "x" },
                        { type = "text", text = "y" },
                    }},
                    { role = "user", content = {
                        { type = "text", text = "b" },
                        { type = "text", text = "c" },
                    }},
                    -- a plain string is forwarded as is, whatever the role
                    { role = "assistant", content = "z" },
                },
            }, ctx)

            assert(type(r.messages[1].content) == "table", "user single block is an array")
            assert(#r.messages[1].content == 1, "one part")
            assert(r.messages[1].content[1].type == "text", "part type")
            assert(r.messages[1].content[1].text == "a", "part text")

            assert(r.messages[2].content == "xy", "assistant blocks concatenated: "
                   .. tostring(r.messages[2].content))

            assert(#r.messages[3].content == 2, "user keeps both blocks")
            assert(r.messages[4].content == "z", "string content untouched")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]



=== TEST 64: tool_choice follows the declared tool name
--- config
    location /t {
        content_by_lua_block {
            local converter = require("apisix.plugins.ai-protocols.converters.anthropic-messages-to-openai-chat")
            local ctx = { var = {} }

            local r = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "my tool!x", input_schema = { type = "object" } }},
                tool_choice = { type = "tool", name = "my tool!x" },
            }, ctx)
            local declared = r.tools[1]["function"].name
            assert(r.tool_choice["function"].name == declared,
                   "tool_choice must name the declared tool: " .. r.tool_choice["function"].name)
            assert(ctx.anthropic_tool_name_map[declared] == "my tool!x", "declared tool mapped")

            -- a tool_choice naming a tool that was never declared is left alone,
            -- and must not invent a mapping the upstream can never produce
            local ctx2 = { var = {} }
            local r2 = converter.convert_request({
                model = "m", max_tokens = 100,
                messages = {{ role = "user", content = "hi" }},
                tools = {{ name = "real_tool", input_schema = { type = "object" } }},
                tool_choice = { type = "tool", name = "ghost tool" },
            }, ctx2)
            assert(r2.tool_choice["function"].name == "ghost tool", "undeclared name untouched")
            assert(ctx2.anthropic_tool_name_map == nil, "no mapping for an undeclared tool")
            ngx.say("OK")
        }
    }
--- response_body
OK
--- no_error_log
[error]
