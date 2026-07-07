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

    # Two response-path moderation backends share one route:
    #   * Lakera Guard on 6724 -- flags when the scanned text contains
    #     "injection" (the assembled streamed completion), else clean.
    #   * Aliyun text moderation on 6725 -- always returns "safe".
    # ai-aliyun-content-moderation has the higher priority (1029) and runs its
    # final_packet body filter before ai-lakera-guard (1028).
    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6724;
            default_type 'application/json';
            location /v2/guard {
                content_by_lua_block {
                    local core = require("apisix.core")
                    local fixture_loader = require("lib.fixture_loader")
                    ngx.req.read_body()
                    local body = ngx.req.get_body_data() or ""
                    local fixture_name = "lakera/scan-clean.json"
                    if core.string.find(body, "injection") then
                        fixture_name = "lakera/scan-flagged.json"
                    end
                    local content, load_err = fixture_loader.load(fixture_name)
                    if not content then
                        ngx.status = 500
                        ngx.say(load_err)
                        return
                    end
                    ngx.status = 200
                    ngx.print(content)
                }
            }
        }
        server {
            listen 6725;
            default_type 'application/json';
            location / {
                content_by_lua_block {
                    require("lib.server").aliyun_moderation()
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: create a route chaining ai-lakera-guard (output/block) after ai-aliyun-content-moderation (default priorities)
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
                          "provider": "openai-compatible",
                          "auth": { "header": { "Authorization": "Bearer token" } },
                          "options": { "model": "gpt-4" },
                          "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" },
                          "ssl_verify": false
                      },
                      "ai-lakera-guard": {
                          "api_key": "test-key",
                          "lakera_endpoint": "http://127.0.0.1:6724/v2/guard",
                          "direction": "output",
                          "action": "block"
                      },
                      "ai-aliyun-content-moderation": {
                          "endpoint": "http://127.0.0.1:6725",
                          "region_id": "cn-shanghai",
                          "access_key_id": "fake-key-id",
                          "access_key_secret": "fake-key-secret",
                          "check_request": false,
                          "check_response": true
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



=== TEST 2: a flagged streamed response is still scanned and blocked by ai-lakera-guard when chained after ai-aliyun-content-moderation
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "say something bad" } ], "stream": true }
--- more_headers
X-AI-Fixture: openai/chat-streaming-injection.sse
--- error_code: 200
--- response_body_like eval
qr/\A(?!.*injection payload).*"content":"Response blocked by Lakera Guard".*\[DONE\]/s
--- error_log
ai-lakera-guard: response flagged by Lakera Guard



=== TEST 3: a clean streamed response still passes through the chain to the client
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "say hello" } ], "stream": true }
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- error_code: 200
--- response_body_like eval
qr/\A(?!.*Response blocked by Lakera Guard).*Hello.*\[DONE\]/s



=== TEST 4: split usage and done chunks produce exactly one terminal event
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "say hello" } ], "stream": true }
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
X-AI-Fixture-Flush-Events: true
--- error_code: 200
--- response_body_like eval
qr/\A(?!.*\[DONE\].*\[DONE\]).*Hello.*\[DONE\]/s
