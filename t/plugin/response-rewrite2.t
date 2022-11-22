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

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {body = "test"},
                {filters = {
                    {
                        regex = "l",
                        replace = "m",
                    },
                }},
                {body = "test", filters = {
                    {
                        regex = "l",
                        replace = "m",
                    },
                }},
                {filters = {}},
                {filters = {
                    {regex = "l"},
                }},
                {filters = {
                    {
                        regex = "",
                        replace = "m",
                    },
                }},
                {filters = {
                    {
                        regex = "l",
                        replace = "m",
                        scope = ""
                    },
                }},
            }
            local plugin = require("apisix.plugins.response-rewrite")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body eval
qr/done
done
failed to validate dependent schema for "filters|body": value wasn't supposed to match schema
property "filters" validation failed: expect array to have at least 1 items
property "filters" validation failed: failed to validate item 1: property "replace" is required
property "filters" validation failed: failed to validate item 1: property "regex" validation failed: string too short, expected at least 1, got 0
property "filters" validation failed: failed to validate item 1: property "scope" validation failed: matches none of the enum values/



=== TEST 2: add plugin with valid filters
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                filters = {
                    {
                        regex = "Hello",
                        scope = "global",
                        replace = "World",
                        options = "jo"
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



=== TEST 3:  add plugin with invalid filter required filed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                filters = {
                    {
                        regex = "Hello",
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "filters" validation failed: failed to validate item 1: property "replace" is required



=== TEST 4:  add plugin with invalid filter scope
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                filters = {
                    {
                        regex = "Hello",
                        scope = "two",
                        replace = "World",
                        options = "jo"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "filters" validation failed: failed to validate item 1: property "scope" validation failed: matches none of the enum values



=== TEST 5:  add plugin with invalid filter empty value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                filters = {
                    {
                        regex = "",
                        replace = "world"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "filters" validation failed: failed to validate item 1: property "regex" validation failed: string too short, expected at least 1, got 0



=== TEST 6:  add plugin with invalid filter regex options
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                filters = {
                    {
                        regex = "hello",
                        replace = "HELLO",
                        options = "h"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- error_code eval
200
--- response_body
regex "hello" validation failed: unknown flag "h" (flags "h")



=== TEST 7: set route with filters and vars expr
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: check http body that matches filters
--- request
GET /hello
--- response_body
test world



=== TEST 9: filter substitute global
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "l",
                                    "replace": "t",
                                    "scope": "global"
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: check http body that substitute global
--- request
GET /hello
--- response_body
hetto wortd



=== TEST 11: filter replace with empty
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": ""
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: check http body that replace with empty
--- request
GET /hello
--- response_body
 world



=== TEST 13: filter replace with words
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "\\w\\S+$",
                                    "replace": "*"
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: check http body that replace with words
--- request
GET /hello
--- response_body
hello *



=== TEST 15: set multiple filters
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "HELLO"
                                },
                                {
                                    "regex": "L",
                                    "replace": "T"
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: check http body that set multiple filters
--- request
GET /hello
--- response_body
HETLO world



=== TEST 17: filters no any match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "test",
                                    "replace": "TEST"
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
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: check http body that filters no any match
--- request
GET /hello
--- response_body
hello world



=== TEST 19: schema check for headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {add = {
                    {"headers:"}
                }},
                {remove = {
                    {"headers:"}
                }},
                {set = {
                    {"headers"}
                }},
                {set = {
                    {[""] = 1}
                }},
                {set = {
                    {["a"] = true}
                }},
            }) do
                local plugin = require("apisix.plugins.response-rewrite")
                local ok, err = plugin.check_schema({headers = case})
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("done")
                end
            end
    }
}
--- response_body eval
"property \"headers\" validation failed: object matches none of the required\n" x 5



=== TEST 20: add headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "add": [
                                    "Cache-Control: no-cache",
                                    "Cache-Control : max-age=0, must-revalidate"
                                ]
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: hit
--- request
GET /hello
--- response_headers
Cache-Control: no-cache, max-age=0, must-revalidate



=== TEST 22: set headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "add": [
                                    "Cache-Control: no-cache"
                                ],
                                "set": {
                                    "Cache-Control": "max-age=0, must-revalidate"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: hit
--- request
GET /hello
--- response_headers
Cache-Control: max-age=0, must-revalidate



=== TEST 24: remove headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "add": [
                                    "Set-Cookie: <cookie-name>=<cookie-value>; Max-Age=<number>"
                                ],
                                "set": {
                                    "Cache-Control": "max-age=0, must-revalidate"
                                },
                                "remove": [
                                    "Set-Cookie",
                                    "Cache-Control"
                                ]
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello"]
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: hit
--- request
GET /hello
--- response_headers
Cache-Control:
Set-Cookie:
