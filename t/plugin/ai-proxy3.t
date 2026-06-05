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
