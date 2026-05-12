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

BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

use t::APISIX 'no_plan';

log_level("debug");
repeat_each(1);
no_long_string();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6724;

            default_type 'application/json';

            location /v2/guard-500 {
                content_by_lua_block {
                    ngx.log(ngx.WARN, "ai-lakera-guard-test-mock: returning 500")
                    ngx.status = 500
                    ngx.print('{"error":"simulated lakera failure"}')
                }
            }

            location /v2/guard-slow {
                content_by_lua_block {
                    ngx.log(ngx.WARN, "ai-lakera-guard-test-mock: sleeping past timeout")
                    ngx.sleep(0.5)
                    ngx.status = 200
                    ngx.print('{"flagged":false,"breakdown":[]}')
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: create /chat-fail-closed route — endpoint points at /v2/guard-500, fail_open=false (default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-fail-closed",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer test-llm-token"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-lakera-guard": {
                        "endpoint": {
                          "url": "http://127.0.0.1:6724/v2/guard-500",
                          "api_key": "test-api-key"
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



=== TEST 2: Lakera 500 with fail_open=false blocks request with deny body + error log
--- request
POST /chat-fail-closed
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- error_code: 200
--- response_body_like eval
qr/Request blocked by security guard/
--- error_log eval
qr/\[error\].*ai-lakera-guard: scan failed/



=== TEST 3: create /chat-fail-open route with fail_open=true and Lakera endpoint /v2/guard-500
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-fail-open",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer test-llm-token"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-lakera-guard": {
                        "fail_open": true,
                        "endpoint": {
                          "url": "http://127.0.0.1:6724/v2/guard-500",
                          "api_key": "test-api-key"
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



=== TEST 4: Lakera 500 with fail_open=true lets request through with warn log
--- request
POST /chat-fail-open
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: lakera/chat-clean.json
--- error_code: 200
--- response_body_like eval
qr/1\+1 equals 2/
--- error_log eval
qr/\[warn\].*ai-lakera-guard: scan failed, fail_open=true so proceeding/
--- no_error_log eval
qr/\[error\].*ai-lakera-guard: scan failed/



=== TEST 5: create /chat-output-fail-closed route — direction=output, /v2/guard-500, fail_open=false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-output-fail-closed",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer test-llm-token"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-lakera-guard": {
                        "direction": "output",
                        "endpoint": {
                          "url": "http://127.0.0.1:6724/v2/guard-500",
                          "api_key": "test-api-key"
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



=== TEST 6: response-side scan failure with fail_open=false replaces harmful LLM body with deny + error log
--- request
POST /chat-output-fail-closed
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: lakera/chat-harmful-response.json
--- error_code: 200
--- response_body_like eval
qr/Request blocked by security guard/
--- response_body_unlike eval
qr/kill the process safely/
--- error_log eval
qr/\[error\].*ai-lakera-guard: response scan failed/



=== TEST 7: create /chat-output-fail-open route — direction=output, /v2/guard-500, fail_open=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-output-fail-open",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer test-llm-token"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-lakera-guard": {
                        "direction": "output",
                        "fail_open": true,
                        "endpoint": {
                          "url": "http://127.0.0.1:6724/v2/guard-500",
                          "api_key": "test-api-key"
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



=== TEST 8: response-side scan failure with fail_open=true lets harmful LLM body through with warn log
--- request
POST /chat-output-fail-open
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: lakera/chat-harmful-response.json
--- error_code: 200
--- response_body_like eval
qr/kill the process safely/
--- error_log eval
qr/\[warn\].*ai-lakera-guard: response scan failed, fail_open=true so proceeding/



=== TEST 9: create /chat-timeout route — timeout_ms=100 against /v2/guard-slow (500ms)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat-timeout",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai",
                          "auth": {
                              "header": {
                                  "Authorization": "Bearer test-llm-token"
                              }
                          },
                          "override": {
                              "endpoint": "http://127.0.0.1:1980"
                          }
                      },
                      "ai-lakera-guard": {
                        "endpoint": {
                          "url": "http://127.0.0.1:6724/v2/guard-slow",
                          "api_key": "test-api-key",
                          "timeout_ms": 100
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



=== TEST 10: Lakera timeout with fail_open=false blocks request with deny body + error log
--- request
POST /chat-timeout
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- error_code: 200
--- response_body_like eval
qr/Request blocked by security guard/
--- error_log eval
qr/\[error\].*ai-lakera-guard: scan failed.*timeout/
