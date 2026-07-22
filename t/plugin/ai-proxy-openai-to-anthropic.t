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
});

run_tests();

__DATA__

=== TEST 1: convert_request – system role becomes top-level system, max_tokens defaulted
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local body = {
                model = "claude-3-5-sonnet",
                messages = {
                    { role = "system", content = "You are a mathematician" },
                    { role = "user", content = "What is 1+1?" },
                },
            }
            local out, err = c.convert_request(body, { var = {} })
            assert(out, err)
            assert(out.system == "You are a mathematician", "system: " .. tostring(out.system))
            assert(#out.messages == 1, "messages count: " .. #out.messages)
            assert(out.messages[1].role == "user")
            assert(out.max_tokens == 4096, "max_tokens: " .. tostring(out.max_tokens))
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 2: convert_request – max_completion_tokens maps to max_tokens
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_request({
                messages = {{ role = "user", content = "hi" }},
                max_completion_tokens = 256,
            }, { var = {} })
            assert(out.max_tokens == 256, "max_tokens: " .. tostring(out.max_tokens))
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 3: convert_request – streaming is rejected
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out, err = c.convert_request({
                messages = {{ role = "user", content = "hi" }},
                stream = true,
            }, { var = {} })
            assert(out == nil, "expected nil")
            ngx.say(err)
        }
    }
--- response_body
streaming is not yet supported for openai-chat to anthropic-messages conversion



=== TEST 4: convert_request – missing messages returns error
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out, err = c.convert_request({ model = "x" }, { var = {} })
            assert(out == nil, "expected nil")
            ngx.say(err)
        }
    }
--- response_body
missing messages



=== TEST 5: convert_request – tools and tool_choice converted to Anthropic format
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_request({
                messages = {{ role = "user", content = "weather?" }},
                tools = {{
                    type = "function",
                    ["function"] = {
                        name = "get_weather",
                        description = "Get weather",
                        parameters = { type = "object", properties = {} },
                    },
                }},
                tool_choice = "required",
            }, { var = {} })
            assert(out.tools[1].name == "get_weather", "tool name")
            assert(out.tools[1].input_schema, "input_schema present")
            assert(out.tools[1]["function"] == nil, "no function wrapper")
            assert(out.tool_choice.type == "any", "tool_choice: " .. core.json.encode(out.tool_choice))
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 6: convert_request – assistant tool_calls and tool result conversion
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_request({
                messages = {
                    { role = "user", content = "weather in SF?" },
                    {
                        role = "assistant",
                        tool_calls = {{
                            id = "call_1",
                            type = "function",
                            ["function"] = {
                                name = "get_weather",
                                arguments = '{"location":"SF"}',
                            },
                        }},
                    },
                    { role = "tool", tool_call_id = "call_1", content = "sunny" },
                },
            }, { var = {} })
            -- assistant message becomes content array with a tool_use block
            local asst = out.messages[2]
            assert(asst.role == "assistant", "asst role")
            assert(asst.content[1].type == "tool_use", "tool_use block")
            assert(asst.content[1].input.location == "SF", "decoded input")
            -- tool message becomes user message with a tool_result block
            local tool_msg = out.messages[3]
            assert(tool_msg.role == "user", "tool result role")
            assert(tool_msg.content[1].type == "tool_result", "tool_result block")
            assert(tool_msg.content[1].tool_use_id == "call_1", "tool_use_id")
            -- internal grouping marker must not leak into the body
            assert(tool_msg._tool_result_group == nil, "marker leaked")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 7: convert_response – Anthropic message converted to OpenAI chat completion
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_response({
                id = "msg_1",
                type = "message",
                role = "assistant",
                model = "claude-3-5-sonnet",
                content = {{ type = "text", text = "Hello!" }},
                stop_reason = "end_turn",
                usage = { input_tokens = 10, output_tokens = 5 },
            }, { var = { llm_model = "claude-3-5-sonnet" } })
            assert(out.object == "chat.completion", "object")
            assert(out.choices[1].message.content == "Hello!", "content")
            assert(out.choices[1].finish_reason == "stop", "finish_reason")
            assert(out.usage.prompt_tokens == 10, "prompt_tokens")
            assert(out.usage.completion_tokens == 5, "completion_tokens")
            assert(out.usage.total_tokens == 15, "total_tokens")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 8: convert_response – tool_use becomes OpenAI tool_calls
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_response({
                id = "msg_2",
                content = {{
                    type = "tool_use",
                    id = "toolu_1",
                    name = "get_weather",
                    input = { location = "SF" },
                }},
                stop_reason = "tool_use",
                usage = { input_tokens = 8, output_tokens = 12 },
            }, { var = {} })
            local tc = out.choices[1].message.tool_calls[1]
            assert(tc.id == "toolu_1", "id")
            assert(tc.type == "function", "type")
            assert(tc["function"].name == "get_weather", "name")
            local args = core.json.decode(tc["function"].arguments)
            assert(args.location == "SF", "arguments")
            assert(out.choices[1].finish_reason == "tool_calls", "finish_reason")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 9: convert_response – Anthropic error mapped to OpenAI error
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local out = c.convert_response({
                type = "error",
                error = { type = "invalid_request_error", message = "bad" },
            }, { var = {} })
            assert(out.error, "error present")
            assert(out.error.message == "bad", "message")
            assert(out.error.type == "invalid_request_error", "type")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 10: convert_headers – Authorization Bearer becomes x-api-key
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local headers = {
                ["authorization"] = "Bearer sk-abc",
                ["x-stainless-lang"] = "js",
                ["openai-organization"] = "org",
                ["content-type"] = "application/json",
            }
            c.convert_headers(headers)
            assert(headers["x-api-key"] == "sk-abc", "x-api-key")
            assert(headers["authorization"] == nil, "authorization stripped")
            assert(headers["anthropic-version"] == "2023-06-01", "anthropic-version")
            assert(headers["x-stainless-lang"] == nil, "x-stainless stripped")
            assert(headers["openai-organization"] == nil, "openai- stripped")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 11: convert_headers – existing x-api-key from route auth is preserved
--- config
    location /t {
        content_by_lua_block {
            local c = require("apisix.plugins.ai-protocols.converters" ..
                              ".openai-chat-to-anthropic-messages")
            local headers = {
                ["authorization"] = "Bearer client-key",
                ["x-api-key"] = "route-key",
            }
            c.convert_headers(headers)
            assert(headers["x-api-key"] == "route-key", "route key preserved")
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 12: Set up route – anthropic-compatible provider, OpenAI client body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "anthropic-compatible",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            }
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



=== TEST 13: OpenAI request to native Anthropic upstream – response converted to OpenAI shape
--- request
POST /anything
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- error_code: 200
--- response_body eval
qr/(?=.*"object":"chat\.completion")(?=.*"content":"Hello! How can I help you\?")(?=.*"finish_reason":"stop")/s



=== TEST 14: Converted request reaches upstream as native Anthropic format (system top-level)
--- request
POST /anything
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
test-type: anthropic-system
--- error_code: 200
--- response_body eval
qr/"content":"Hello! How can I help you\?"/



=== TEST 15: Tool definitions are converted to native Anthropic format on the wire
--- request
POST /anything
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "user", "content": "weather?" } ], "tools": [ { "type": "function", "function": { "name": "get_weather", "description": "Get weather", "parameters": { "type": "object" } } } ] }
--- more_headers
X-AI-Fixture: anthropic/messages-tool-use.json
test-type: anthropic-tools
--- error_code: 200
--- response_body eval
qr/(?=.*"tool_calls")(?=.*"name":"get_weather")/s



=== TEST 16: Anthropic tool_use response surfaces as OpenAI tool_calls
--- request
POST /anything
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "user", "content": "weather in SF?" } ] }
--- more_headers
X-AI-Fixture: anthropic/messages-tool-use.json
--- error_code: 200
--- response_body eval
qr/(?=.*"tool_calls")(?=.*"id":"toolu_abc123")(?=.*"name":"get_weather")(?=.*"finish_reason":"tool_calls")/s



=== TEST 17: Streaming request is rejected with 400
--- request
POST /anything
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "user", "content": "hi" } ], "stream": true }
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- error_code: 400
--- response_body eval
qr/streaming is not yet supported/
