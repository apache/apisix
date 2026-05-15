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

Validates that upstream nginx variables ($upstream_status, $upstream_addr,
$upstream_response_time, $upstream_uri, etc.) are populated when ai-proxy
sends requests via cosocket transport.

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
});

run_tests();

__DATA__

=== TEST 1: set route with ai-proxy pointing to mock server
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
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
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



=== TEST 2: non-streaming request populates upstream variables in access log
--- request
POST /anything
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:\d+ 200 [\d.]+/



=== TEST 3: streaming request populates upstream variables in access log
--- request
POST /anything
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- error_code: 200
--- access_log eval
qr/127\.0\.0\.1:\d+ 200 [\d.]+/



=== TEST 4: upstream_uri and upstream_host are populated with the target path and host
--- request
POST /anything
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- access_log eval
qr{http://127\.0\.0\.1/v1/chat/completions}



=== TEST 5: set route with serverless plugin to log upstream_response_length
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
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(_, ctx) ngx.log(ngx.WARN, 'upstream_response_length: ', ngx.var.upstream_response_length) end"]
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



=== TEST 6: non-streaming request has non-zero upstream_response_length
--- request
POST /anything
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- error_log eval
qr/upstream_response_length: [1-9]\d*/
--- no_error_log
upstream_response_length: 0



=== TEST 7: streaming request has non-zero upstream_response_length
--- request
POST /anything
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- error_code: 200
--- error_log eval
qr/upstream_response_length: [1-9]\d*/
--- no_error_log
upstream_response_length: 0
