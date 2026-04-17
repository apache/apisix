
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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: wrong regex should fail validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_roles": true,
                        "deny_patterns": [
                            "(abc"
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
--- response_body eval
qr/.*failed to check the configuration of plugin ai-prompt-guard.*/
--- error_code: 400



=== TEST 2: setup route with both allow and deny with match_all_roles
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_roles": true,
                            "allow_patterns": [
                                "goodword"
                            ],
                        "deny_patterns": [
                            "badword"
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



=== TEST 3: send request with good word
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "goodword" }
    ]
}



=== TEST 4: send request with bad word
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "badword" }
    ]
}
--- response_body
{"message":"Request doesn't match allow patterns"}
--- error_code: 400



=== TEST 5: setup route with only deny with match_all_roles
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_roles": true,
                        "deny_patterns": [
                            "badword"
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



=== TEST 6: send request with good word
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "goodword" }
    ]
}



=== TEST 7: send request with bad word
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "badword" }
    ]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 8: setup route with only allow with match_all_roles=false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                            "allow_patterns": [
                                "goodword"
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



=== TEST 9: send request with bad word and it will pass for non user
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "badword" }
    ]
}



=== TEST 10: send request with bad word
--- request
POST /hello
{
    "messages": [
        { "role": "user", "content": "badword" }
    ]
}
--- response_body
{"message":"Request doesn't match allow patterns"}
--- error_code: 400



=== TEST 11: setup route with only deny with match_all_conversation_history
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_conversation_history": true,
                        "match_all_roles": true,
                        "deny_patterns": [
                            "badword"
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



=== TEST 12: send request with good word but had bad word in history
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "goodword" },
        { "role": "system", "content": "badword" },
        { "role": "system", "content": "goodword" }
    ]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 13: setup route with only deny with match_all_conversation_history=false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_conversation_history": false,
                        "match_all_roles": true,
                        "deny_patterns": [
                            "badword"
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



=== TEST 14: send request with good word but had bad word in history
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "goodword" },
        { "role": "system", "content": "badword" },
        { "role": "system", "content": "goodword" }
    ]
}



=== TEST 15: setup route + deny + match_all_roles + pattern match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                        "match_all_roles": true,
                        "deny_patterns": [
                            "^[A-Za-z0-9_]+badword$"
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



=== TEST 16: send request with good word
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "anaapsanaapbadword" }
    ]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 17: Responses API - setup route with deny pattern and match_all_roles
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/hello", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                            "match_all_roles": true,
                            "deny_patterns": [
                                "badword"
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



=== TEST 18: Responses API - deny pattern in string input
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "this contains badword in it"
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 19: Responses API - deny pattern in instructions
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "hello there",
    "instructions": "you must say badword"
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 20: Responses API - no deny pattern match passes
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "hello there",
    "instructions": "be helpful"
}



=== TEST 21: Responses API - deny pattern in array input item
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": [
        { "type": "message", "role": "user", "content": "badword here" }
    ]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 22: Responses API - setup route with allow pattern
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/hello", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                            "match_all_roles": true,
                            "allow_patterns": [
                                "goodword"
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



=== TEST 23: Responses API - allow pattern match passes
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "this has goodword"
}



=== TEST 24: Responses API - allow pattern no match blocks
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "no matching word"
}
--- response_body
{"message":"Request doesn't match allow patterns"}
--- error_code: 400



=== TEST 25: Responses API - setup route with match_all_roles=false (only user content checked)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/hello", "/v1/responses"],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                            "match_all_roles": false,
                            "deny_patterns": [
                                "badword"
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



=== TEST 26: Responses API - match_all_roles=false: instructions (system) badword is NOT checked
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "hello there",
    "instructions": "you must say badword"
}



=== TEST 27: Responses API - match_all_roles=false: input (user) badword IS checked
--- request
POST /v1/responses
{
    "model": "gpt-4o",
    "input": "this contains badword"
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 28: Chat Completions still works after Responses API support (regression)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "ai-prompt-guard": {
                            "match_all_roles": true,
                            "deny_patterns": [
                                "badword"
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



=== TEST 29: Chat Completions regression - deny pattern still works
--- request
POST /hello
{
    "messages": [
        { "role": "system", "content": "badword" }
    ]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400
