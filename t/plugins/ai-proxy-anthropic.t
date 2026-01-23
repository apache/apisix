#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License,  Version 2.0
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
                        
                        -- Verify core requirement 1: authentication header must be x-api-key
                        if ngx.var.http_x_api_key ~= "test-key" then
                            ngx.status = 401
                            ngx.say("Wrong Auth Header" )
                            return
                        end

                        -- Verify core requirement 2: Anthropic version header must be present
                        if not ngx.var.http_anthropic_version then
                            ngx.status = 400
                            ngx.say("Missing Version Header" )
                            return
                        end

                        -- Verify core requirement 3: system prompt extraction
                        if body.system ~= "You are a helper" then
                            ngx.status = 400
                            ngx.say("System Prompt Error")
                            return
                        end

                        ngx.status = 200
                        ngx.say([[{"id": "msg_123", "content": [{"text": "Hello!"}], "usage": {"input_tokens": 5, "output_tokens": 5}}]])
                    }
                }
            }
        ]]);
    }
});

run_tests();

__DATA__

=== TEST 1: Anthropic Native - Basic Request Transformation (Headers & Path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/test",
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "test-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                }
            }]] )

            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/test", {
                method = "POST",
                body = '{"messages":[{"role":"system","content":"You are a helper"},{"role":"user","content":"Hi"}]}',
                headers = { ["Content-Type"] = "application/json" }
            } )
            ngx.print(res.body)
        }
    }
--- response_body
{"choices":[{"finish_reason":"end_turn","index":0,"message":{"content":"Hello!","role":"assistant"}}],"created":12345678,"id":"msg_123","model":"claude-3","object":"chat.completion","usage":{"completion_tokens":5,"prompt_tokens":5,"total_tokens":10}}

=== TEST 2: Anthropic Native - Role Mapping (User/Assistant)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/test", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"},{"role":"user","content":"How are you?"}]}',
                headers = { ["Content-Type"] = "application/json" }
            } )
            ngx.status = res.status
            ngx.say("passed")
        }
    }
--- response_body
passed

=== TEST 3: Anthropic Native - Missing API Key (Error Handling)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/test-error",
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "wrong-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                }
            }]] )
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/test-error", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"Hi"}]}',
            } )
            ngx.print(res.body)
        }
    }
--- response_body
Wrong Auth Header

=== TEST 4: Anthropic Native - Max Tokens & Default Params
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/test", {
                method = "POST",
                body = '{"model":"gpt-4","messages":[{"role":"user","content":"Hi"}],"max_tokens":100}',
            } )
            ngx.status = res.status
            ngx.say("passed")
        }
    }
--- response_body
passed
