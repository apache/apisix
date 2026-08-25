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

    # The behaviour under test lives in ai-providers/base.lua and only depends on
    # body_reader() reporting a transport error, so it is the same for either HTTP
    # client. Pinning one keeps the error string this file asserts on stable.
    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy
  - ai-proxy-multi
  - ai-aliyun-content-moderation
plugin_attr:
    ai-proxy:
        http_client: lua-resty-http
_EOC_
    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $user_yaml_config);
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 6724;

        # Commits a 200 SSE response, flushes one valid event, then drops the
        # connection without the terminating chunk and without [DONE]. Takes over
        # the raw socket because nginx would otherwise append a well-formed
        # end-of-chunked-body on its own.
        location /v1/chat/completions-truncate {
            content_by_lua_block {
                require("lib.truncated_sse").serve({
                    'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
                    .. '"choices":[{"index":0,"delta":{"content":"hello"},'
                    .. '"finish_reason":null}]}\\n\\n',
                })
            }
        }

        # Same, but a usage event lands before the truncation, so
        # ctx.var.llm_response_text is set and the content-moderation
        # final_packet path runs on the last body_filter pass.
        location /v1/chat/completions-usage-then-truncate {
            content_by_lua_block {
                require("lib.truncated_sse").serve({
                    'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
                    .. '"choices":[{"index":0,"delta":{"content":"hello"},'
                    .. '"finish_reason":null}]}\\n\\n',
                    'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
                    .. '"choices":[],"usage":{"prompt_tokens":1,'
                    .. '"completion_tokens":1,"total_tokens":2}}\\n\\n',
                })
            }
        }

        # First hit commits the 200 SSE headers and drops the connection before
        # any body byte; later hits stream a complete response. Reproduces a read
        # error that happens before anything reaches the client.
        location /v1/chat/completions-abort-once {
            content_by_lua_block {
                require("lib.truncated_sse").serve_abort_once()
            }
        }

        # Aliyun content-moderation endpoint.
        location / {
            content_by_lua_block {
                local content = require("lib.fixture_loader").load("aliyun/moderation-safe.json")
                ngx.status = 200
                ngx.header["Content-Type"] = "application/json"
                ngx.print(content)
            }
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: ai-proxy route on the truncating upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/truncated",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": {"header": {"Authorization": "Bearer test"}},
                        "options": {"model": "gpt-4", "stream": true},
                        "override": {
                            "endpoint": "http://127.0.0.1:6724/v1/chat/completions-truncate"
                        },
                        "ssl_verify": false
                    }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: a read error after partial output leaves the committed 200 alone
--- request
POST /truncated
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_body eval
qq{data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}\n\n}
--- error_log
failed to read response chunk: closed
--- no_error_log
exits with http status code
attempt to set ngx.status
failed to keepalive connection
--- timeout: 10



=== TEST 3: ai-proxy-multi route on the truncating upstream, with http_5xx fallback
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/truncated",
                "plugins": {
                    "ai-proxy-multi": {
                        "fallback_strategy": ["http_5xx"],
                        "ssl_verify": false,
                        "instances": [
                            {"name":"first","provider":"openai","weight":1,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-truncate"}},
                            {"name":"second","provider":"openai","weight":1,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-truncate"}}
                        ]
                    }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: no fallback after partial output -- exactly one upstream request is billed
--- request
POST /truncated
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_body eval
qq{data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}\n\n}
--- grep_error_log eval
qr/sending request to LLM server/
--- grep_error_log_out
sending request to LLM server
--- no_error_log
falling back to
attempt to set ngx.status
--- timeout: 10



=== TEST 5: ai-proxy-multi route on the abort-before-body upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/truncated",
                "plugins": {
                    "ai-proxy-multi": {
                        "fallback_strategy": ["http_5xx"],
                        "ssl_verify": false,
                        "instances": [
                            {"name":"first","provider":"openai","weight":1,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-abort-once"}},
                            {"name":"spare","provider":"openai","weight":0,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-abort-once"}}
                        ]
                    }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: a read error before the first downstream byte still falls back
--- request
POST /truncated
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_body_like eval
qr/data: \[DONE\]/
--- error_log
failed to read response chunk: closed
falling back to
--- timeout: 10



=== TEST 7: ai-proxy + ai-aliyun-content-moderation on the usage-then-truncate upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/truncated",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": {"header": {"Authorization": "Bearer test"}},
                        "options": {"model": "gpt-4", "stream": true},
                        "override": {
                            "endpoint": "http://127.0.0.1:6724/v1/chat/completions-usage-then-truncate"
                        },
                        "ssl_verify": false
                    },
                    "ai-aliyun-content-moderation": {
                        "endpoint": "http://127.0.0.1:6724",
                        "region_id": "cn-shanghai",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "risk_level_bar": "high",
                        "check_request": false,
                        "check_response": true,
                        "stream_check_mode": "final_packet"
                    }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: a truncated stream is never terminated with a synthesized [DONE]
--- request
POST /truncated
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_body_like eval
# The moderation plugin re-encodes every event, so the key order is not stable
# enough to assert the body verbatim: require the delivered content and the
# risk_level annotation that proves the final_packet branch ran, and reject a
# [DONE] anywhere in the response.
qr/^(?!.*\[DONE\])(?=.*"content":"hello")(?=.*"risk_level":"none")/s
--- error_log
failed to read response chunk: closed
--- timeout: 10
