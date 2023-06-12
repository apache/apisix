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
});

run_tests();


__DATA__

=== TEST 1: schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local data = {
                {
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
                },
                {
                    rules = {
                        {
                            case = {
                                {"uri", "==", "/hello"}
                            }
                        }
                    }
                },
                {
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
                },
                {
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
                },
                {
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
                },
                {
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
                },
                {
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
                }
            }

            for _, conf in ipairs(data) do
                local ok, err = plugin.check_schema(conf)
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("done")
                end
            end
        }
    }
--- response_body
done
property "rules" validation failed: failed to validate item 1: property "actions" is required
property "rules" validation failed: failed to validate item 1: property "actions" validation failed: failed to validate item 1: expect array to have at least 1 items
failed to validate the 'return' action: property "code" is required
failed to validate the 'return' action: property "code" validation failed: wrong type: expected integer, got string
property "rules" validation failed: failed to validate item 1: property "case" validation failed: expect array to have at least 1 items
unsupported action: fake



=== TEST 2: set plugin
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



=== TEST 3: trigger workflow
--- request
GET /hello
--- error_code: 403



=== TEST 4: multiple conditions in one case
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



=== TEST 5: missing match the only case
--- request
GET /hello?foo=bad



=== TEST 6: trigger workflow
--- request
GET /hello?foo=bar
--- error_code: 403
--- response_body
{"error_msg":"rejected by workflow"}



=== TEST 7: multiple cases with different actions
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



=== TEST 8: trigger one case
--- request
GET /hello
--- error_code: 403



=== TEST 9: trigger another case
--- request
GET /hello2
--- error_code: 401



=== TEST 10: match case in order
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



=== TEST 11: both case 1&2 matched, trigger the first cases
--- request
GET /hello?foo=bar
--- error_code: 403



=== TEST 12: case 1 mismatched, trigger the second cases
--- request
GET /hello?foo=bad
--- error_code: 401



=== TEST 13: all cases mismatched, pass to upstream
--- request
GET /hello1
--- response_body
hello1 world



=== TEST 14: schema check(limit-count)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.workflow")
            local data = {
                {
                    rules = {
                        {
                            case = {
                                {"uri", "==", "/hello"}
                            },
                            actions = {
                                {
                                    "limit-count",
                                    {count = 2, time_window = 60, rejected_code = 503, key = 'remote_addr'}
                                }
                            }
                        }
                    }
                },
                {
                    rules = {
                        {
                            case = {
                                {"uri", "==", "/hello"}
                            },
                            actions = {
                                {
                                    "limit-count",
                                    {count = 2}
                                }
                            }
                        }
                    }
                },
                {
                    rules = {
                        {
                            case = {
                                {"uri", "==", "/hello"}
                            },
                            actions = {
                                {
                                    "limit-count",
                                    {time_window = 60}
                                }
                            }
                        }
                    }
                },
                {
                    rules = {
                        {
                            case = {
                                {"uri", "==", "/hello"}
                            },
                            actions = {
                                {
                                    "limit-count",
                                    {
                                        count = 2,
                                        time_window = 60,
                                        rejected_code = 503,
                                        group = "services_1"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            for _, conf in ipairs(data) do
                local ok, err = plugin.check_schema(conf)
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("done")
                end
            end
        }
    }
--- response_body
done
failed to validate the 'limit-count' action: property "time_window" is required
failed to validate the 'limit-count' action: property "count" is required
failed to validate the 'limit-count' action: group is not supported



=== TEST 15: set actions as limit-count
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
                                                "limit-count",
                                                {
                                                    "count": 3,
                                                    "time_window": 60,
                                                    "rejected_code": 503,
                                                    "key": "remote_addr"
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



=== TEST 16: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 503]



=== TEST 17: the conf in actions is isolation
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
                                        "limit-count",
                                        {
                                            count = 3,
                                            time_window = 60,
                                            rejected_code = 503,
                                            key = "remote_addr"
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello1"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 3,
                                            time_window = 60,
                                            rejected_code = 503,
                                            key = "remote_addr"
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



=== TEST 18: cross-hit case 1 and case 2, up limit by isolation
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello", "GET /hello1",
"GET /hello", "GET /hello1", "GET /hello", "GET /hello1"]
--- error_code eval
[200, 200, 200, 200, 200, 200, 503, 503]



=== TEST 19: multiple conditions in one case
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
                                            "OR",
                                            ["arg_foo", "==", "bar"],
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



=== TEST 20: trigger workflow
--- request
GET /hello
--- error_code: 403
--- response_body
{"error_msg":"rejected by workflow"}
