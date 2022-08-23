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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();


__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        },
                        actions = {
                            {
                                "return",
                                {
                                    code = 403
                                }
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: missing actions
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "actions" is required/



=== TEST 3: actions have at least 1 items
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        },
                        actions = {
                            {
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/expect array to have at least 1 items/



=== TEST 4: code is needed if action is return
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        },
                        actions = {
                            {
                                "return",
                                {
                                    status = 403
                                }
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "code" is required/



=== TEST 5: the required type of code is number
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        },
                        actions = {
                            {
                                "return",
                                {
                                    code = "403"
                                }
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "code" validation failed: wrong type: expected integer, got string/



=== TEST 6: bad conf of case
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {

                        },
                        actions = {
                            {
                                "return",
                                {
                                    code = 403
                                }
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "case" validation failed: expect array to have at least 1 items/



=== TEST 7: unsupported action
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        case = {
                            {"uri", "==", "/hello"}
                        },
                        actions = {
                            {
                                "fake",
                                {
                                    code = 403
                                }
                            }
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body
unsupported action: fake



=== TEST 8: set plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "workflow": {
                                "rules": [
                                    {
                                        "case": [
                                            ["uri", "==", "/hello"]
                                        ],
                                        "actions": [
                                            [
                                                "return",
                                                {
                                                    "code": 403
                                                }
                                            ]
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 9: trigger workflow
--- request
GET /hello
--- error_code: 403



=== TEST 10: multiple conditions in one case
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "workflow": {
                                "rules": [
                                    {
                                        "case": [
                                            ["uri", "==", "/hello"],
                                            ["arg_foo", "==", "bar"]
                                        ],
                                        "actions": [
                                            [
                                                "return",
                                                {
                                                    "code": 403
                                                }
                                            ]
                                        ]
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 11: missing match the only case
--- request
GET /hello?foo=bad



=== TEST 12: trigger workflow
--- request
GET /hello?foo=bar
--- error_code: 403
--- response_body
{"error_msg":"rejected by workflow"}



=== TEST 13: multiple cases with different actions
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/*",
                plugins = {
                    workflow = {
                        rules = {
                            {
                                case = {
                                    {"uri", "==", "/hello"}
                                },
                                actions = {
                                    {
                                        "return",
                                        {
                                            code = 403
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello2"}
                                },
                                actions = {
                                    {
                                        "return",
                                        {
                                            code = 401
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: trigger one case
--- request
GET /hello
--- error_code: 403



=== TEST 15: trigger another case
--- request
GET /hello2
--- error_code: 401



=== TEST 16: match case in order
# rules is an array, match in the order of the index of the array,
# when cases are matched, actions are executed and do not continue
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/*",
                plugins = {
                    workflow = {
                        rules = {
                            {
                                case = {
                                    {"arg_foo", "==", "bar"}
                                },
                                actions = {
                                    {
                                        "return",
                                        {
                                            code = 403
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello"}
                                },
                                actions = {
                                    {
                                        "return",
                                        {
                                            code = 401
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 17: both case 1&2 matched, trigger the first cases
--- request
GET /hello?foo=bar
--- error_code: 403



=== TEST 18: case 1 mismatched, trigger the second cases
--- request
GET /hello?foo=bad
--- error_code: 401



=== TEST 19: all cases mismatched, pass to upstream
--- request
GET /hello1
--- response_body
hello1 world
