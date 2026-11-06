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



=== TEST 2: reject empty and non-object prompt arrays
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local empty_code = t('/apisix/admin/routes/18',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/invalid-empty",
                    "plugins": {"ai-prompt-decorator": {"prepend": []}}
                }]]
            )
            local item_code = t('/apisix/admin/routes/19',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/invalid-item",
                    "plugins": {"ai-prompt-decorator": {"append": ["bad"]}}
                }]]
            )
            ngx.say("empty=", empty_code, " item=", item_code)
        }
    }
--- response_body
empty=400 item=400



=== TEST 3: configure protocol-aware decoration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/20',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/v1/messages", "/model/test/converse", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {"127.0.0.1:1980": 1}
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend": [
                                {"role": "system", "content": "first system"},
                                {"role": "assistant", "content": "first assistant"}
                            ],
                            "append": [
                                {"role": "assistant", "content": "last assistant"},
                                {"role": "system", "content": "last system"}
                            ]
                        },
                        "proxy-rewrite": {
                            "uri": "/echo"
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



=== TEST 4: decorate Anthropic system and conversation fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            ngx.sleep(1)
            local code, body = t('/v1/messages',
                ngx.HTTP_POST,
                [[{
                    "model": "claude-test",
                    "system": "existing system",
                    "messages": [{"role": "user", "content": "question"}]
                }]],
                [[{
                    "model": "claude-test",
                    "system": [
                        {"type": "text", "text": "first system"},
                        {"type": "text", "text": "existing system"},
                        {"type": "text", "text": "last system"}
                    ],
                    "messages": [
                        {"role": "assistant", "content": "first assistant"},
                        {"role": "user", "content": "question"},
                        {"role": "assistant", "content": "last assistant"}
                    ]
                }]]
            )
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



=== TEST 5: decorate Bedrock system and conversation fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/model/test/converse',
                ngx.HTTP_POST,
                [[{
                    "system": [{"text": "existing system"}],
                    "messages": [{"role": "user", "content": [{"text": "question"}]}]
                }]],
                [[{
                    "system": [
                        {"text": "first system"},
                        {"text": "existing system"},
                        {"text": "last system"}
                    ],
                    "messages": [
                        {"role": "assistant", "content": [{"text": "first assistant"}]},
                        {"role": "user", "content": [{"text": "question"}]},
                        {"role": "assistant", "content": [{"text": "last assistant"}]}
                    ]
                }]]
            )
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



=== TEST 6: preserve roles when decorating Responses input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/v1/responses',
                ngx.HTTP_POST,
                [[{
                    "model": "gpt-test",
                    "instructions": "existing system",
                    "input": "question"
                }]],
                [[{
                    "model": "gpt-test",
                    "instructions": "first system\nexisting system\nlast system",
                    "input": [
                        {"type": "message", "role": "assistant", "content": "first assistant"},
                        {"type": "message", "role": "user", "content": "question"},
                        {"type": "message", "role": "assistant", "content": "last assistant"}
                    ]
                }]]
            )
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



=== TEST 7: fail_mode controls unsupported request handling
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/23',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/unsupported",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {"127.0.0.1:1980": 1}
                    },
                    "plugins": {
                        "ai-prompt-decorator": {
                            "prepend": [{"role": "system", "content": "decorate"}],
                            "fail_mode": "error"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t('/unsupported', ngx.HTTP_POST, '{"plain":"json"}')
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/Request format not recognized by ai-prompt-decorator/



=== TEST 8: reject oversized request body with 413
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/24',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/decorator-small",
                    "plugins": {
                        "ai-prompt-decorator": {
                            "max_req_body_size": 10,
                            "prepend": [{"role": "system", "content": "decorate"}]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local http = require("resty.http").new()
            local res = assert(http:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/decorator-small",
                {
                    method = "POST",
                    body = '{"messages":[{"role":"user","content":"too large"}]}',
                    headers = {['Content-Type'] = 'application/json'},
                }
            ))
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 413
--- response_body eval
qr/greater than the maximum size/



=== TEST 9: test prepend
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



=== TEST 10: sanity: configure append only
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



=== TEST 11: test append
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



=== TEST 12: sanity: configure append and prepend both
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



=== TEST 13: test append
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



=== TEST 14: verify no message accumulation across multiple requests
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



=== TEST 15: sanity: configure neither append nor prepend should fail
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



=== TEST 16: Responses API - configure prepend for Responses API test
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



=== TEST 17: Responses API - prepend sets instructions field
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



=== TEST 18: Responses API - prepend prepends to existing instructions
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



=== TEST 19: Responses API - configure append for Responses API test
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



=== TEST 20: Responses API - append to string input
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



=== TEST 21: Responses API - append to array input
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



=== TEST 22: Responses API - configure both prepend and append
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



=== TEST 23: Responses API - prepend and append together
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



=== TEST 24: Chat Completions still works after Responses API support (regression)
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
