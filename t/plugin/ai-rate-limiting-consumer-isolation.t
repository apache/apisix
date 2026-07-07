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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";
    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
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

=== TEST 1: set route with consumers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 2: add consumer jack1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "key-auth": {
                            "key": "jack1"
                        },
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60
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
--- request
GET /t
--- response_body
passed



=== TEST 3: add consumer jack2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack2",
                    "plugins": {
                        "key-auth": {
                            "key": "jack2"
                        },
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60
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
--- request
GET /t
--- response_body
passed



=== TEST 4: reject the 3rd request
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
apikey: jack1
X-AI-Fixture: openai/chat-model-echo.json
--- error_code eval
[200, 200, 200, 503]



=== TEST 5: reject the 3rd request
--- pipelined_requests eval
[
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
    "POST /ai\n" . "{ \"messages\": [ { \"role\": \"system\", \"content\": \"You are a mathematician\" }, { \"role\": \"user\", \"content\": \"What is 1+1?\"} ] }",
]
--- more_headers
Authorization: Bearer token
apikey: jack2
X-AI-Fixture: openai/chat-model-echo.json
--- error_code eval
[200, 200, 200, 503]
