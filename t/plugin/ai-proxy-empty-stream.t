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

    # Mock upstream reproducing the customer incident: the LLM answers with a
    # 200 and an SSE content type, then closes the connection without ever
    # writing a single body byte. No converter is involved (OpenAI-format
    # client against an OpenAI-compatible provider).
    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name empty_sse;
            listen 7751;

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.status = 200
                    ngx.header["Content-Type"] = "text/event-stream"
                    -- headers only, zero body bytes, then EOF
                    ngx.eof()
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with a streaming ai-proxy against the empty-SSE upstream
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
                                "model": "gpt-4",
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://localhost:7751"
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



=== TEST 2: upstream returns an empty SSE stream
--- request
POST /anything
{"messages": [{"role": "user", "content": "hi"}]}
--- more_headers
Content-Type: application/json
--- error_code: 502
--- no_error_log
attempt to index local 'up_conf'
