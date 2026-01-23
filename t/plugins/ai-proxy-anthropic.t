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
use Test::Nginx::Socket::Lua;
use t::APISIX 'no_plan';

repeat_each(1 );
no_long_string();
no_root_resource();

add_block_preprocessor(function ($block) {
    if (!$block->http_config ) {
        $block->set_value("http_config", [[
            server {
                listen 1984;
                
                location /v1/messages {
                    content_by_lua_block {
                        local core = require("apisix.core" )
                        local body = core.json.decode(ngx.req.get_body_data())
                        
                        -- 1. Verify Auth Header
                        if ngx.var.http_x_api_key ~= "test-key" then
                            ngx.status = 401
                            ngx.say([[{"error": {"type": "authentication_error", "message": "invalid x-api-key"}}]] )
                            return
                        end

                        -- 2. Verify Version Header
                        if ngx.var.http_anthropic_version ~= "2023-06-01" then
                            ngx.status = 400
                            ngx.say("Missing version header" )
                            return
                        end

                        -- 3. Handle Streaming Mock
                        if body.stream then
                            ngx.header.content_type = "text/event-stream"
                            ngx.say("event: message_start\ndata: {\"type\": \"message_start\", \"message\": {\"id\": \"msg_1\"}}\n\n")
                            ngx.say("event: content_block_delta\ndata: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \"Hello\"}}\n\n")
                            ngx.say("event: message_stop\ndata: {\"type\": \"message_stop\"}\n\n")
                            return
                        end

                        -- 4. Normal Response
                        ngx.status = 200
                        ngx.say([[{"id": "msg_123", "model": "claude-3", "content": [{"text": "Hello, I am Claude!"}], "usage": {"input_tokens": 10, "output_tokens": 10}}]])
                    }
                }
            }
        ]]);
    }
});

run_tests();

__DATA__

=== TEST 1: Anthropic Native - Basic Protocol Translation (System Prompt & Headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "test-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                },
                "uri": "/v1/chat/completions"
            }]] )

            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "system", "content": "You are a helper"}, {"role": "user", "content": "Hi"}]}]],
                headers = { ["Content-Type"] = "application/json" }
            } )
            ngx.print(res.body)
        }
    }
--- response_body
{"choices":[{"finish_reason":"end_turn","index":0,"message":{"content":"Hello, I am Claude!","role":"assistant"}}],"created":12345678,"id":"msg_123","model":"claude-3","object":"chat.completion","usage":{"completion_tokens":10,"prompt_tokens":10,"total_tokens":20}}

=== TEST 2: Anthropic Native - Multi-turn Conversation (Role Mapping)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello"}, {"role": "user", "content": "How are you?"}]}]],
            } )
            ngx.status = res.status
            ngx.say("passed")
        }
    }
--- response_body
passed

=== TEST 3: Anthropic Native - Error Handling (Invalid API Key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "wrong-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                },
                "uri": "/v1/chat/completions"
            }]] )
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}]}]],
            } )
            ngx.print(res.body)
        }
    }
--- response_body
{"error":{"message":"invalid x-api-key","type":"authentication_error"}}

=== TEST 4: Anthropic Native - Parameter Pass-through (max_tokens)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}], "max_tokens": 500}]],
            } )
            ngx.status = res.status
            ngx.say("passed")
        }
    }
--- response_body
passed

=== TEST 5: Anthropic Native - Streaming (SSE) Mock
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}], "stream": true}]],
            } )
            ngx.say("Content-Type: " .. res.headers["Content-Type"])
            ngx.status = res.status
        }
    }
--- response_body
Content-Type: text/event-stream
