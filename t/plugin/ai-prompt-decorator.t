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

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sanity: configure prepend only
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "some content"
                                }
                            ]
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



=== TEST 2: test prepend
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "some content" },
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: sanity: configure append only
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "append":[
                                {
                                    "role": "system",
                                    "content": "some content"
                                }
                            ]
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



=== TEST 4: test append
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" },
                            { "role": "system", "content": "some content" }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 5: sanity: configure append and prepend both
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "append":[
                                {
                                    "role": "system",
                                    "content": "some append"
                                }
                            ],
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "some prepend"
                                }
                            ]
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



=== TEST 6: test append
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "some prepend" },
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" },
                            { "role": "system", "content": "some append" }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: verify no message accumulation across multiple requests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Configure route with prepend
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "system prompt"
                                }
                            ]
                        }
                    }
            }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("failed to configure route")
                return
            end

            -- First request
            local code1, body1, actual_resp1 = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "user", "content": "first message" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "system prompt" },
                            { "role": "user", "content": "first message" }
                        ]
                    }]]
            )

            if code1 >= 300 then
                ngx.status = code1
                ngx.say("first request failed")
                return
            end

            -- Second request should have the same structure, not accumulating history
            local code2, body2, actual_resp2 = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "user", "content": "second message" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "system prompt" },
                            { "role": "user", "content": "second message" }
                        ]
                    }]]
            )

            if code2 >= 300 then
                ngx.status = code2
                ngx.say("second request failed")
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: sanity: configure neither append nor prepend should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
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
--- response_body_eval
qr/.*failed to check the configuration of plugin ai-prompt-decorator err.*/
--- error_code: 400



=== TEST 9: Responses API - configure prepend for Responses API test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/echo", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "Be helpful"
                                }
                            ]
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



=== TEST 10: Responses API - prepend sets instructions field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/v1/responses',
                    ngx.HTTP_POST,
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?"
                    }]],
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?",
                        "instructions": "Be helpful"
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 11: Responses API - prepend prepends to existing instructions
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/v1/responses',
                    ngx.HTTP_POST,
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?",
                        "instructions": "You are a math tutor"
                    }]],
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?",
                        "instructions": "Be helpful\nYou are a math tutor"
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: Responses API - configure append for Responses API test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/echo", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "append":[
                                {
                                    "role": "user",
                                    "content": "Please be concise"
                                }
                            ]
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



=== TEST 13: Responses API - append to string input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/v1/responses',
                    ngx.HTTP_POST,
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?"
                    }]],
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?\nPlease be concise"
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: Responses API - append to array input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/v1/responses',
                    ngx.HTTP_POST,
                    [[{
                        "model": "gpt-4o",
                        "input": [
                            { "type": "message", "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    [[{
                        "model": "gpt-4o",
                        "input": [
                            { "type": "message", "role": "user", "content": "What is 1+1?" },
                            { "type": "message", "role": "user", "content": "Please be concise" }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 15: Responses API - configure both prepend and append
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/echo", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "Be helpful"
                                }
                            ],
                            "append":[
                                {
                                    "role": "user",
                                    "content": "Please be concise"
                                }
                            ]
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



=== TEST 16: Responses API - prepend and append together
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, actual_resp = t('/v1/responses',
                    ngx.HTTP_POST,
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?"
                    }]],
                    [[{
                        "model": "gpt-4o",
                        "input": "What is 1+1?\nPlease be concise",
                        "instructions": "Be helpful"
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 17: Chat Completions still works after Responses API support (regression)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Configure route with prepend
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend":[
                                {
                                    "role": "system",
                                    "content": "some content"
                                }
                            ]
                        }
                    }
            }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("failed to configure route")
                return
            end

            local code, body, actual_resp = t('/echo',
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "user", "content": "hello" }
                        ]
                    }]],
                    [[{
                        "messages": [
                            { "role": "system", "content": "some content" },
                            { "role": "user", "content": "hello" }
                        ]
                    }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
