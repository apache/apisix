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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6820;
            default_type 'application/json';
            # Mock LLM endpoint. It logs whether the client's Cookie reached it,
            # so tests can distinguish the transparent proxy path (ai-proxy, which
            # SHOULD forward client headers) from a self-contained internal request
            # (ai-request-rewrite, which must NOT leak them to a third party).
            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.log(ngx.WARN, "llm-recv-cookie:",
                            ngx.var.http_cookie or "none")
                    ngx.req.read_body()
                    ngx.status = 200
                    ngx.say('{"choices":[{"message":{"content":"rewritten body"}}]}')
                }
            }
            # Upstream target for the proxied (post-rewrite) request.
            location /anything {
                content_by_lua_block {
                    ngx.status = 200
                    ngx.say("upstream-ok")
                }
            }
        }
_EOC_
    $block->set_value("http_config", $http_config);

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-request-rewrite
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: configure ai-request-rewrite pointing at the mock LLM
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-request-rewrite": {
                        "prompt": "rewrite this",
                        "auth": { "header": { "Authorization": "Bearer llm-key" } },
                        "provider": "openai",
                        "override": {
                            "endpoint": "http://127.0.0.1:6820/v1/chat/completions"
                        },
                        "ssl_verify": false
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:6820": 1 }
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: ai-request-rewrite's internal LLM call must not receive the client Cookie
--- request
POST /anything
some content to rewrite
--- more_headers
Content-Type: text/plain
Cookie: session=super-secret
--- response_body
upstream-ok
--- error_log
llm-recv-cookie:none
--- no_error_log
llm-recv-cookie:session=super-secret



=== TEST 3: configure ai-proxy-multi routing to the mock LLM
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/chat",
                "plugins": {
                    "ai-proxy-multi": {
                        "instances": [
                            {
                                "name": "openai",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer llm-key" } },
                                "options": { "model": "gpt-4" },
                                "override": {
                                    "endpoint": "http://127.0.0.1:6820/v1/chat/completions"
                                }
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: ai-proxy is a transparent proxy and DOES forward the client Cookie
--- request
POST /chat
{"messages":[{"role":"user","content":"hello"}]}
--- more_headers
Content-Type: application/json
Cookie: session=proxy-secret
--- error_log
llm-recv-cookie:session=proxy-secret
--- no_error_log
[error]
