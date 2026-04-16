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

=== TEST 1: minimal viable configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "openai",
                auth = {
                    header = {
                        Authorization =  "Bearer token"
                    }
                }
            })

            if not ok then
                ngx.print(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: missing prompt field should not pass
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                provider = "openai",
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
property "prompt" is required



=== TEST 3: missing auth field should not pass
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "openai",
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "auth" is required



=== TEST 4: missing provider field should not pass
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
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
property "provider" is required



=== TEST 5: provider must be one of: deepseek, openai, aimlapi, openai-compatible
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "invalid-provider",
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
property "provider" validation failed: matches none of the enum values



=== TEST 6: provider deepseek
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "deepseek",
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
passed



=== TEST 7: provider openai-compatible
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
                },
                override = {
                    endpoint = "http://127.0.0.1:1980"
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
passed



=== TEST 8: override endpoint works
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
                            "prompt": "some prompt",
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/random"
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
                ngx.say(body)
                return
            end


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )
            local json = require("cjson.safe")
            local response_data = json.decode(actual_body)

            if response_data.data == 'return by random endpoint' then
                ngx.say("passed")
            else
                ngx.say(actual_body)
            end
        }
    }
--- response_body
passed



=== TEST 9: set route with wrong auth header
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
                            "prompt": "some prompt",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrong-token"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            if code == 500 then
                ngx.say('passed')
                return
            end
        }
    }

--- error_log
LLM service returned error status: 401
--- response_body
passed



=== TEST 10: set route with correct query param
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
                            "prompt": "some prompt",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            local json = require("cjson.safe")
            local response_data = json.decode(actual_body)

            if response_data.data == "some prompt some random content" then
                ngx.say("passed")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
passed



=== TEST 11: set route with wrong query param
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
                            "prompt": "some prompt",
                            "auth": {
                                "query": {
                                    "api_key": "wrong_key"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            if code == 500 then
                ngx.say('passed')
                return
            end
        }
    }

--- error_log
LLM service returned error status: 401
--- response_body
passed



=== TEST 12: prompt passed correctly to LLM service
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
                                "endpoint": "http://127.0.0.1:1980"
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


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            local json = require("cjson.safe")
            local response_data = json.decode(actual_body)

            if response_data.data == "some prompt to test some random content" then
                ngx.say("passed")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
passed



=== TEST 13: check LLM bad request
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
                                "endpoint": "http://127.0.0.1:1980/bad_request"
                            },
                            "ssl_verify": false,
                            "options": {
                                "model": "check_options_model",
                                "temperature": 0.5,
                                "max_tokens": 100,
                                "top_p": 1,
                                "frequency_penalty": 0,
                                "presence_penalty": 0
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

            if code == 500 then
                ngx.say('passed')
                return
            end
        }
    }
--- error_log
LLM service returned error status: 400
--- response_body
passed



=== TEST 14: check LLM internal server error
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
                                "endpoint": "http://127.0.0.1:1980/internalservererror"
                            },
                            "ssl_verify": false,
                            "options": {
                                "model": "check_options_model",
                                "temperature": 0.5,
                                "max_tokens": 100,
                                "top_p": 1,
                                "frequency_penalty": 0,
                                "presence_penalty": 0
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

            if code == 500 then
                ngx.say('passed')
                return
            end
        }
    }
--- error_log
LLM service returned error status: 500
--- response_body
passed



=== TEST 15: provider aimlapi
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "aimlapi",
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
passed
