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

=== TEST 1: Set up route – Anthropic protocol auto-detected via exact /v1/messages URI (Non-stream)
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
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



=== TEST 2: Send Anthropic request to /v1/messages and verify protocol conversion
--- request
POST /v1/messages
{ "model": "claude-3-5-sonnet-20241022", "messages": [ { "role": "user","content": "hello" } ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/"text":"1 \+ 1 = 2\."/



=== TEST 3: Missing messages field returns 400
--- request
POST /v1/messages
{ "model": "claude-3-5-sonnet-20241022" }
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body
{"error_msg":"missing messages"}



=== TEST 4: Malformed JSON body returns 400
--- request
POST /v1/messages
this is not valid json
--- more_headers
Authorization: Bearer token
Content-Type: application/json
--- error_code: 400



=== TEST 5: messages field is wrong type (non-array)
--- request
POST /v1/messages
{ "model": "claude-3-5-sonnet-20241022", "messages": "hello" }
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body
{"error_msg":"missing messages"}



=== TEST 6: messages is an empty array
--- request
POST /v1/messages
{ "model": "claude-3-5-sonnet-20241022", "messages": [] }
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body
{"error_msg":"missing messages"}



=== TEST 7: Set up route for stream test – exact URI /v1/messages triggers Anthropic detection
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "claude-3-5-sonnet-20241022",
                                "stream": true
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



=== TEST 8: Send Anthropic stream request and verify SSE conversion
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/openai-to-anthropic-stream.sse",
                },
                body = [[{
                    "model": "claude-3-5-sonnet-20241022",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            ngx.print(table.concat(results, ""))
        }
    }
--- error_code: 200
--- response_body eval
qr/event: message_start\ndata:.*?"type":"message_start".*?event: content_block_start\ndata:.*?event: content_block_delta\ndata:.*?"text":"Hello".*?event: content_block_delta\ndata:.*?"text":" world".*?event: content_block_stop\ndata:.*?event: message_delta\ndata:.*?event: message_stop\ndata:/s



=== TEST 9: Set up route for system prompt conversion test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
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



=== TEST 10: System prompt is converted to OpenAI messages[0] with role=system
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/system-prompt-ok.json",
                },
                body = [[{
                    "model": "claude-3-5-sonnet-20241022",
                    "system": "You are a helpful assistant.",
                    "messages": [{"role": "user", "content": "hello"}]
                }]],
            })

            local body = res:read_body()
            ngx.status = res.status
            ngx.print(body)
        }
    }
--- error_code: 200
--- response_body eval
qr/"text":"system prompt ok"/



=== TEST 11: Set up route for tool calling conversion test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
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



=== TEST 12: Tool calling request/response conversion (Anthropic <-> OpenAI)
--- request
POST /v1/messages
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"What is the weather in Paris?"}],"tools":[{"name":"get_weather","description":"Get weather","input_schema":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}]}
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-tools.json
--- error_code: 200
--- response_body eval
qr/(?=.*"stop_reason":"tool_use")(?=.*"type":"tool_use")(?=.*"name":"get_weather")/s



=== TEST 13: Set up route for null finish_reason test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "stream": true
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



=== TEST 14: message_stop emitted only once (finish_reason as JSON null must not trigger end events)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/null-finish-reason.sse",
                },
                body = [[{
                    "model": "gpt-4o",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")

            -- count occurrences of message_stop
            local count = 0
            for _ in body:gmatch('"type":"message_stop"') do
                count = count + 1
            end

            -- also verify the final content delta and message_delta were emitted
            local has_final_content = body:find('"text":"!"', 1, true) ~= nil
            local has_message_delta = body:find('"type":"message_delta"', 1, true) ~= nil

            if count ~= 1 then
                ngx.say("FAIL: message_stop appeared " .. count .. " times, expected 1")
            elseif not has_final_content then
                ngx.say("FAIL: final content '!' not found in body")
            elseif not has_message_delta then
                ngx.say("FAIL: message_delta event not found in body")
            else
                ngx.say("OK: message_stop appeared exactly once")
            end
        }
    }
--- error_code: 200
--- response_body
OK: message_stop appeared exactly once



=== TEST 15: Set up route for OpenRouter-style double finish_reason chunk test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "stream": true
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



=== TEST 16: OpenRouter sends two finish_reason chunks — message_stop must appear exactly once, no empty content_block_delta
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/openrouter-double-finish.sse",
                },
                body = [[{
                    "model": "gpt-4o",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")

            -- Count message_stop occurrences (must be exactly 1)
            local stop_count = 0
            for _ in body:gmatch('"type":"message_stop"') do
                stop_count = stop_count + 1
            end

            -- Verify no empty text_delta events are emitted (finish_reason chunks with
            -- empty content must not produce content_block_delta events).
            -- content_block_start legitimately contains text:"", so we check the
            -- per-event data for content_block_delta specifically.
            local empty_delta_count = 0
            for event_data in body:gmatch('event: content_block_delta\ndata: ([^\n]+)') do
                local decoded = require("cjson.safe").decode(event_data)
                if decoded and decoded.delta and decoded.delta.text == "" then
                    empty_delta_count = empty_delta_count + 1
                end
            end

            -- Verify content tokens are present
            local has_hi = body:find('"text":"Hi"', 1, true) ~= nil
            local has_bang = body:find('"text":"!"', 1, true) ~= nil

            if stop_count ~= 1 then
                ngx.say("FAIL: message_stop appeared " .. stop_count .. " times, expected 1")
            elseif empty_delta_count > 0 then
                ngx.say("FAIL: found " .. empty_delta_count .. " empty text_delta(s), expected 0")
            elseif not has_hi then
                ngx.say("FAIL: content 'Hi' not found")
            elseif not has_bang then
                ngx.say("FAIL: content '!' not found")
            else
                ngx.say("OK: two finish_reason chunks handled correctly")
            end
        }
    }
--- error_code: 200
--- response_body
OK: two finish_reason chunks handled correctly



=== TEST 17: Set up route for DeepSeek-style usage:null crash test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "deepseek-chat",
                                "stream": true
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



=== TEST 18: DeepSeek sends usage:null on non-final chunks — must not crash, content must be preserved
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/deepseek-usage-null.sse",
                },
                body = [[{
                    "model": "deepseek-chat",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")

            local stop_count = 0
            for _ in body:gmatch('"type":"message_stop"') do
                stop_count = stop_count + 1
            end

            local has_hi = body:find('"text":"Hi"', 1, true) ~= nil
            local has_bang = body:find('"text":"!"', 1, true) ~= nil
            local has_message_start = body:find('event: message_start', 1, true) ~= nil

            if not has_message_start then
                ngx.say("FAIL: message_start not found (possible 500 crash)")
            elseif stop_count ~= 1 then
                ngx.say("FAIL: message_stop appeared " .. stop_count .. " times, expected 1")
            elseif not has_hi then
                ngx.say("FAIL: content 'Hi' not found")
            elseif not has_bang then
                ngx.say("FAIL: content '!' not found")
            else
                ngx.say("OK: DeepSeek usage:null chunks handled correctly")
            end
        }
    }
--- error_code: 200
--- response_body
OK: DeepSeek usage:null chunks handled correctly



=== TEST 19: Set up route for first-chunk role+content test (OpenRouter pattern)
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "stream": true
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



=== TEST 20: First chunk contains both role and content simultaneously — content must not be lost
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/openrouter-first-chunk.sse",
                },
                body = [[{
                    "model": "gpt-4o",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")

            local has_hello = body:find('"hello"', 1, true) ~= nil
            local has_world = body:find('" world"', 1, true) ~= nil
            local stop_count = 0
            for _ in body:gmatch('"type":"message_stop"') do
                stop_count = stop_count + 1
            end

            if not has_hello then
                ngx.say("FAIL: content 'hello' lost from first chunk")
            elseif not has_world then
                ngx.say("FAIL: content ' world' lost from second chunk")
            elseif stop_count ~= 1 then
                ngx.say("FAIL: message_stop appeared " .. stop_count .. " times, expected 1")
            else
                ngx.say("OK: first-chunk role+content preserved correctly")
            end
        }
    }
--- error_code: 200
--- response_body
OK: first-chunk role+content preserved correctly



=== TEST 21: sse.encode output must end with \n\n (SSE spec requires blank-line event terminator)
--- config
    location /t {
        content_by_lua_block {
            local sse = require("apisix.plugins.ai-transport.sse")

            -- Test a named event (e.g. message_stop)
            local out = sse.encode({ type = "message_stop", data = '{"type":"message_stop"}' })
            if out:sub(-2) ~= "\n\n" then
                ngx.say("FAIL: named event does not end with \\n\\n, got: " ..
                        string.format("%q", out:sub(-4)))
                return
            end

            -- Test a plain data event (type == "message", no event: line)
            local out2 = sse.encode({ type = "message", data = '{"foo":"bar"}' })
            if out2:sub(-2) ~= "\n\n" then
                ngx.say("FAIL: data-only event does not end with \\n\\n, got: " ..
                        string.format("%q", out2:sub(-4)))
                return
            end

            ngx.say("OK: sse.encode output ends with \\n\\n")
        }
    }
--- response_body
OK: sse.encode output ends with \n\n



=== TEST 22: empty SSE data frames between real chunks must not trigger JSON decode warnings
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/empty-sse-frames.sse",
                },
                body = [[{
                    "model": "gpt-4o",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")
            local has_content = body:find('"text":"Hi"', 1, true) ~= nil
            local has_stop = body:find('"type":"message_stop"', 1, true) ~= nil

            if not has_content then
                ngx.say("FAIL: content 'Hi' not found")
            elseif not has_stop then
                ngx.say("FAIL: message_stop not found")
            else
                ngx.say("OK: empty data frame handled without error")
            end
        }
    }
--- error_code: 200
--- response_body
OK: empty data frame handled without error
--- no_error_log
failed to decode SSE data



=== TEST 23: sse.encode handles edge cases correctly
--- config
    location /t {
        content_by_lua_block {
            local sse = require("apisix.plugins.ai-transport.sse")

            -- empty string data: should still produce a valid SSE frame ending with \n\n
            local out1 = sse.encode({ type = "content_block_delta", data = "" })
            if out1:sub(-2) ~= "\n\n" then
                ngx.say("FAIL: empty data does not end with \\n\\n")
                return
            end

            -- large payload: must not be truncated, must end with \n\n
            local large_data = string.rep("x", 8192)
            local out2 = sse.encode({ type = "content_block_delta", data = large_data })
            if out2:sub(-2) ~= "\n\n" then
                ngx.say("FAIL: large payload does not end with \\n\\n")
                return
            end
            if not out2:find(large_data, 1, true) then
                ngx.say("FAIL: large payload was truncated")
                return
            end

            -- special characters in data: quotes, backslashes, newlines must be preserved
            local special_data = '{"text":"line1\\nline2","quote":"\\"hello\\""}'
            local out3 = sse.encode({ type = "content_block_delta", data = special_data })
            if out3:sub(-2) ~= "\n\n" then
                ngx.say("FAIL: special-char data does not end with \\n\\n")
                return
            end
            if not out3:find(special_data, 1, true) then
                ngx.say("FAIL: special characters were mangled")
                return
            end

            ngx.say("OK: sse.encode edge cases passed")
        }
    }
--- response_body
OK: sse.encode edge cases passed



=== TEST 24: Set up route for usage-only final chunk test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "stream": true
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



=== TEST 25: usage in a separate chunk after message_stop — message_delta with usage must be emitted
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/usage-only-final-chunk.sse",
                },
                body = [[{
                    "model": "gpt-4o",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            local results = {}
            while true do
                local chunk, err = res.body_reader()
                if not chunk then break end
                table.insert(results, chunk)
            end

            local body = table.concat(results, "")

            -- message_stop must appear exactly once
            local stop_count = 0
            for _ in body:gmatch('"type":"message_stop"') do
                stop_count = stop_count + 1
            end

            -- At least one message_delta must carry usage (input_tokens + output_tokens)
            local has_usage = body:find('"input_tokens":10', 1, true) ~= nil
                           and body:find('"output_tokens":5', 1, true) ~= nil

            if stop_count ~= 1 then
                ngx.say("FAIL: message_stop appeared " .. stop_count .. " times, expected 1")
            elseif not has_usage then
                ngx.say("FAIL: usage (input_tokens=10, output_tokens=5) not found in stream")
            else
                ngx.say("OK: usage-only chunk produced message_delta with usage")
            end
        }
    }
--- error_code: 200
--- response_body
OK: usage-only chunk produced message_delta with usage
--- no_error_log
[error]



=== TEST 26: Anthropic SSE error event should be logged at warn level
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.ai-protocols.anthropic-messages")
            local event = {
                type = "error",
                data = '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
            }
            local result = proto.parse_sse_event(event, {var = {}}, {})
            ngx.say("type: " .. result.type)
        }
    }
--- response_body
type: done
--- error_log
Anthropic SSE error: type=overloaded_error, message=Overloaded



=== TEST 27: Set up route for response format mismatch test – openai-compatible provider with Anthropic override endpoint
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
                            "provider": "openai-compatible",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "test-model"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/messages"
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



=== TEST 28: Streaming 502 when converter receives mismatched upstream response format
When the client sends Anthropic format (detected via /v1/messages URI) but the provider
is openai-compatible (only supports openai-chat), a converter bridges the gap. If the
upstream endpoint also returns Anthropic-format SSE (instead of OpenAI), the converter
cannot parse any events and the gateway should return 502 instead of crashing.
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            local res, err = httpc:request({
                method = "POST",
                path = "/v1/messages",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Connection"] = "close",
                    ["X-AI-Fixture"] = "protocol-conversion/anthropic-mismatch.sse",
                },
                body = [[{
                    "model": "test-model",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "stream": true
                }]],
            })

            res:read_body()
            ngx.say("status: " .. res.status)
        }
    }
--- response_body
status: 502
--- error_log
streaming response completed without producing any output
