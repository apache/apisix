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

run_tests();

__DATA__

=== TEST 1: Sanity check, transform request to Anthropic format
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local openai_body = {
                model = "claude-3-opus",
                messages = {
                    { role = "system", content = "sys prompt" },
                    { role = "user", content = "hello" }
                }
            }
            local transformed = drv:transform_request(openai_body)
            local json = require("apisix.core.json")
            ngx.say(json.encode(transformed))
        }
    }
--- request
GET /t
--- response_body
{"max_tokens":4096,"messages":[{"content":"hello","role":"user"}],"model":"claude-3-opus","system":"sys prompt"}
--- no_error_log
[error]

=== TEST 2: Transform response from Anthropic format
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local anthropic_res = {
                body = [[{
                    "id": "msg_123",
                    "model": "claude-3-opus",
                    "content": [{"text": "Hello! I am Claude."}],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 10, "output_tokens": 20}
                }]]
            }
            local transformed = drv:transform_response(anthropic_res)
            local json = require("apisix.core.json")
            ngx.say(transformed.choices[1].message.content)
            ngx.say(transformed.usage.total_tokens)
        }
    }
--- request
GET /t
--- response_body
Hello! I am Claude.
30
--- no_error_log
[error]
