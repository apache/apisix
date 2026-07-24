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

=== TEST 1: set access log
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
                            "provider": "openai",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 2: send request
--- request
POST /anything
{"messages":[{"role":"system","content":"You are a mathematician"},{"role":"user","content":"What is 1+1?"}], "model": "gpt-4"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/.*completion_tokens.*/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/chat\/completions\" gpt-4 gpt-3.5-turbo [\d.]+ 23 8.*/



=== TEST 3: proxy to /null-content ai endpoint
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 4: send request
--- request
POST /anything
{"messages":[{"role":"user","content":"What is 1+1?"}], "model": "gpt-4"}
--- more_headers
X-AI-Fixture: openai/null-content.json
--- error_code: 200
--- response_body eval
qr/.*assistant.*/
--- no_error_log



=== TEST 5: create a ai-proxy-multi route with delay streaming ai endpoint(every event delay 200ms)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-3.5-turbo",
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions?delay=true"
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



=== TEST 6: assert access log contains right llm variable
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

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ],
                    "model": "gpt-4"
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            local inspect = require("inspect")
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end
            ngx.print(#final_res .. final_res[6])
        }
    }
--- response_body_like eval
qr/6data: \[DONE\]\n\n/
--- access_log eval
qr/localhost:7737 200 [\d.]+ \"http:\/\/\S+\/v1\/chat\/completions\" gpt-4 gpt-3.5-turbo 2\d\d 15 20.*/



=== TEST 7: set route for built-in access log variable test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/log-vars",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o"
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



=== TEST 8: non-streaming request writes llm built-in vars to access log
--- request
POST /log-vars
{"messages":[{"role":"user","content":"What is 1+1?"}],"model":"gpt-4o","user":"alice"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/.*completion_tokens.*/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 23 8 31 false false 0 alice/



=== TEST 9: streaming request writes llm built-in vars to access log
--- request
POST /log-vars
{"messages":[{"role":"user","content":"Hello"}],"model":"gpt-4o","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-multi-chunk.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 10 2 12 true false 0 /



=== TEST 10: response with cached tokens writes llm_cache_read_input_tokens to access log
--- request
POST /log-vars
{"messages":[{"role":"user","content":"Solve this"}],"model":"gpt-4o"}
--- more_headers
X-AI-Fixture: openai/chat-with-reasoning.json
--- error_code: 200
--- response_body eval
qr/.*completion_tokens.*/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 30 15 45 false false 0 \S* 10 5 0/



=== TEST 11: response with tool calls sets llm_has_tool_calls=true and llm_tool_count
--- request
POST /log-vars
{"messages":[{"role":"user","content":"What is the weather?"}],"model":"gpt-4o","tools":[{"type":"function","function":{"name":"get_weather","parameters":{}}}]}
--- more_headers
X-AI-Fixture: openai/chat-with-tool-calls.json
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 50 20 70 false true 1 /



=== TEST 12: safety_identifier field is used as llm_end_user_id
--- request
POST /log-vars
{"messages":[{"role":"user","content":"Hello"}],"model":"gpt-4o","safety_identifier":"user-xyz"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 23 8 31 false false 0 user-xyz/



=== TEST 13: OpenAI Chat streaming detects tool_calls delta and sets llm_has_tool_calls=true
--- request
POST /log-vars
{"messages":[{"role":"user","content":"What is the weather?"}],"model":"gpt-4o","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming-with-tool-calls.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 15 10 25 true true 0 /



=== TEST 14: set route for Responses API built-in var tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai/v1/responses",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
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



=== TEST 15: Responses API streaming sets llm_cache_read_input_tokens and llm_reasoning_tokens
--- request
POST /ai/v1/responses
{"input":"Hello","model":"gpt-4o-mini","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming-with-cache.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o-mini gpt-4o-mini [\d.]+ 20 5 25 true false 0 \S* 10 0 3/



=== TEST 16: Responses API streaming detects function_call in response.output as tool call
--- request
POST /ai/v1/responses
{"input":"What is the weather?","model":"gpt-4o-mini","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming-with-tool-call.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o-mini gpt-4o-mini [\d.]+ 20 5 25 true true 0 /



=== TEST 17: OpenAI Chat streaming writes cache and reasoning tokens to access log
--- request
POST /log-vars
{"messages":[{"role":"user","content":"Solve this"}],"model":"gpt-4o","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming-with-cache.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o gpt-4o [\d.]+ 30 15 45 true false 0 \S* 10 5 7/



=== TEST 18: Responses API non-streaming writes cache and reasoning tokens to access log
--- request
POST /ai/v1/responses
{"input":"Solve this","model":"gpt-4o-mini"}
--- more_headers
X-AI-Fixture: openai/responses-with-cache.json
--- error_code: 200
--- response_body eval
qr/.*output.*/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"\S+\" gpt-4o-mini gpt-4o-mini [\d.]+ 40 20 60 false false 0 \S* 12 0 8/



=== TEST 19: set route for streaming socket timeout test
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo",
                                "stream": true
                            },
                            "timeout": 500,
                            "override": {
                                "endpoint": "http://localhost:7742"
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



=== TEST 20: mid-stream body_reader error does not log status-after-200 (timeout case)
# Tests the fix for body_reader() errors after output_sent becomes true.
# This test covers timeout (504), but the fix also applies to other errors
# like connection reset (500). Timeout is the most common case and easiest
# to reliably reproduce in tests.
--- http_config
    server {
        server_name stall_ai_sse;
        listen 7742;

        default_type 'text/event-stream';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"

                -- Send enough chunks so the proxy writes at least one
                -- downstream frame (output_sent becomes true).
                for i = 1, 5 do
                    ngx.print('data: {"id":"chatcmpl-1","object":'
                        .. '"chat.completion.chunk","choices":[{"delta":'
                        .. '{"content":"token"},"index":0,'
                        .. '"finish_reason":null}],"usage":null}\\n\\n')
                    ngx.flush(true)
                    ngx.sleep(0.001)
                end

                -- Stall so the proxy-side body_reader() times out
                -- while output_sent is already true. This triggers the
                -- output_sent guard that prevents "attempt to set status
                -- 504 after sending out response status 200" nginx error.
                ngx.sleep(300)
            }
        }
    }
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
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                headers = { ["Content-Type"] = "application/json" },
                path = "/anything",
                body = [[{"messages": [{"role": "user", "content": "hi"}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local chunks = 0
            while true do
                local chunk, rerr = res.body_reader()
                if rerr or not chunk then
                    break
                end
                chunks = chunks + 1
            end

            -- Must receive at least a few chunks before the timeout fires.
            if chunks < 2 then
                ngx.status = 500
                ngx.say("expected at least 2 chunks, got ", chunks)
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- no_error_log
attempt to set status 504 via ngx.exit after sending out
attempt to set status 500 via ngx.exit after sending out
attempt to set ngx.status after sending out
--- error_log
failed to read response chunk
