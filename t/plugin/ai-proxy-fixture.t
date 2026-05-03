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

=encoding utf-8

Validates the fixture-based mock system in t/lib/fixture_loader.lua.
Tests use t/lib/server.lua endpoints backed by t/fixtures/ files instead of
inline content_by_lua_block mock servers.

=cut

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

=== TEST 1: set route pointing to test server (fixture-based mock)
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
                                    "name": "fixture-test",
                                    "provider": "openai",
                                    "weight": 1,
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



=== TEST 2: JSON fixture - OpenAI chat completion
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_body_like eval
qr/"content":\s*"1 \+ 1 = 2\."/
--- response_headers_like
Content-Type: application/json



=== TEST 3: SSE fixture - OpenAI streaming chat completion
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]



=== TEST 4: missing X-AI-Fixture header falls back to auth check
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}
--- error_code: 401
--- response_body_like eval
qr/Unauthorized/



=== TEST 5: nonexistent fixture returns error (direct test)
--- config
    location /t {
        content_by_lua_block {
            local fixture_loader = require("lib.fixture_loader")
            local content, err = fixture_loader.load("nonexistent/does-not-exist.json")
            if not content then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say(content)
        }
    }
--- error_code: 500
--- response_body
fixture not found



=== TEST 6: set route for Anthropic messages endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anthropic",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "fixture-anthropic",
                                    "provider": "anthropic",
                                    "weight": 1,
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



=== TEST 7: JSON fixture - Anthropic messages
--- request
POST /anthropic
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"hello"}],"max_tokens":100}
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- response_body_like eval
qr/"stop_reason":\s*"end_turn"/
--- response_headers_like
Content-Type: application/json



=== TEST 8: SSE fixture - Anthropic streaming messages
--- request
POST /anthropic
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"hello"}],"max_tokens":100,"stream":true}
--- more_headers
X-AI-Fixture: anthropic/messages-streaming.sse
--- response_headers_like
Content-Type: text/event-stream
--- response_body_like
event: message_stop



=== TEST 9: protocol-conversion SSE fixture - DeepSeek usage:null
--- request
POST /anything
{"model":"deepseek-chat","messages":[{"role":"user","content":"hello"}],"stream":true}
--- more_headers
X-AI-Fixture: protocol-conversion/deepseek-usage-null.sse
--- response_headers_like
Content-Type: text/event-stream
--- response_body_like eval
qr/deepseek-chat/



=== TEST 10: model template substitution in fixture
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-model-echo.json
--- response_body_like eval
qr/"model":\s*"gpt-4o"/
--- response_headers_like
Content-Type: application/json



=== TEST 11: custom status code via X-AI-Fixture-Status (direct test)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local ok, err = httpc:connect("127.0.0.1", 1980)
            if not ok then
                ngx.say("connect error: ", err)
                return
            end
            local res, err = httpc:request({
                method = "POST",
                path = "/v1/chat/completions",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["X-AI-Fixture"] = "openai/chat-basic.json",
                    ["X-AI-Fixture-Status"] = "429",
                },
                body = '{"model":"gpt-4o","messages":[]}',
            })
            if not res then
                ngx.say("request error: ", err)
                return
            end
            ngx.say("status: ", res.status)
        }
    }
--- response_body
status: 429



=== TEST 12: path traversal prevention (direct test)
--- config
    location /t {
        content_by_lua_block {
            local fixture_loader = require("lib.fixture_loader")
            local content, err = fixture_loader.load("../../../etc/passwd")
            if not content then
                ngx.say("blocked: ", err)
                return
            end
            ngx.say(content)
        }
    }
--- response_body
blocked: invalid fixture name



=== TEST 13: embeddings fixture
--- request
POST /anything
{"model":"text-embedding-3-small","input":"hello"}
--- more_headers
X-AI-Fixture: openai/embeddings-list.json
--- response_body_like eval
qr/"object":\s*"list"/
--- response_headers_like
Content-Type: application/json



=== TEST 14: tool calling fixture
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"weather in Paris"}]}
--- more_headers
X-AI-Fixture: openai/chat-tools.json
--- response_body_like
"tool_calls"
--- response_headers_like
Content-Type: application/json
