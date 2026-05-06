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

Tests for the passthrough protocol adapter. Verifies that requests whose
body does not match any known AI protocol (e.g. OpenAI Images Generation)
are proxied to the upstream without protocol-specific transformation.

=cut

BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

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

=== TEST 1: set route for images generation (passthrough)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/images/generations",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
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



=== TEST 2: images generation request goes through passthrough protocol
--- request
POST /v1/images/generations
{"model":"dall-e-3","prompt":"A cute baby sea otter","n":1,"size":"1024x1024"}
--- more_headers
X-AI-Fixture: openai/images-generation.json
--- response_body eval
qr/baby sea otter/
--- no_error_log
no matching AI protocol



=== TEST 3: passthrough protocol is detected last (chat still matches)
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



=== TEST 4: request with messages field matches openai-chat, not passthrough
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_body eval
qr/1 \+ 1 = 2\./
--- no_error_log
no matching AI protocol



=== TEST 5: passthrough uses override.endpoint path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/images/generations",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 6: passthrough with override.endpoint uses endpoint path not request URI
--- request
POST /v1/images/generations
{"model":"gpt-4o","prompt":"test"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_body eval
qr/1 \+ 1 = 2\./
--- no_error_log
no matching AI protocol



=== TEST 7: set route with model rewrite for passthrough
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/images/generations",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "dall-e-3-override"
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



=== TEST 8: passthrough rewrites model from options
--- request
POST /v1/images/generations
{"model":"dall-e-2","prompt":"test","n":1}
--- response_body eval
qr/dall-e-3-override/
--- no_error_log
no matching AI protocol



=== TEST 9: protocol detection unit test
--- config
    location /t {
        content_by_lua_block {
            local protocols = require("apisix.plugins.ai-protocols")

            -- chat body matches openai-chat
            local name = protocols.detect({messages = {{role = "user", content = "hi"}}}, {})
            ngx.say("chat: ", name)

            -- embeddings body matches openai-embeddings
            name = protocols.detect({input = "hello"}, {})
            ngx.say("embeddings: ", name)

            -- images body matches passthrough
            name = protocols.detect({prompt = "a cat", model = "dall-e-3"}, {})
            ngx.say("images: ", name)

            -- empty body does NOT match passthrough (requires at least one key)
            name = protocols.detect({}, {})
            ngx.say("empty: ", name)
        }
    }
--- response_body
chat: openai-chat
embeddings: openai-embeddings
images: passthrough
empty: nil
--- no_error_log
no matching AI protocol
