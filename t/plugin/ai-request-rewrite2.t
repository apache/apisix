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
});

run_tests();

__DATA__

=== TEST 1: check plugin options send to llm service correctly
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-request-rewrite": {
                            "prompt": "some prompt to test",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/check_extra_options"
                            },
                            "ssl_verify": false,
                            "options": {
                                "model": "check_options_model",
                                "extra_option": "extra option"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.local:8280": 1
                        }
                    }
                }]]
            )


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            if code == 200 then
                ngx.say('passed')
                return
            end
        }
    }
--- response_body
passed



=== TEST 2: openai-compatible provider should use with override.endpoint
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "openai-compatible",
                auth = {
                    header = {
                        Authorization =  "Bearer token"
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
override.endpoint is required for openai-compatible provider



=== TEST 3: query params in override.endpoint should be sent to LLM
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-request-rewrite": {
                            "prompt": "some prompt to test",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "provider": "openai",
                            "options": {
                                "model": "gpt-35-turbo-instruct"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/test/params/in/overridden/endpoint?some_query=yes"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.local:8280": 1
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



=== TEST 4: send request without body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-request-rewrite": {
                            "prompt": "some prompt to test",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/check_extra_options"
                            },
                            "ssl_verify": false,
                            "options": {
                                "model": "check_options_model",
                                "extra_option": "extra option"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.local:8280": 1
                        }
                    }
                }]]
            )


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                nil,
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            if code == 400 then
                ngx.say('passed')
                return
            end

            ngx.say('failed, got: ', code)
        }
    }
--- error_log eval
qr/missing request body/
--- response_body
passed
