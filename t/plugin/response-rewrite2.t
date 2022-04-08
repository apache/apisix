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
run_tests;

__DATA__

=== TEST 1:  add plugin with valid filters
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
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2:  add plugin with invalid filter required filed
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
--- request
GET /t
--- response_body
property "filters" validation failed: failed to validate item 1: property "replace" is required
--- no_error_log
[error]



=== TEST 3:  add plugin with invalid filter scope
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
--- request
GET /t
--- response_body
property "filters" validation failed: failed to validate item 1: property "scope" validation failed: matches none of the enum values
--- no_error_log
[error]



=== TEST 4:  add plugin with invalid filter empty value
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
--- request
GET /t
--- response_body
property "filters" validation failed: failed to validate item 1: property "regex" validation failed: string too short, expected at least 1, got 0
--- no_error_log
[error]



=== TEST 5:  add plugin with invalid filter regex options
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
--- request
GET /t
--- error_code eval
200
--- response_body
regex "hello" validation failed: unknown flag "h" (flags "h")
--- no_error_log
[error]



=== TEST 6: set route with filters and vars expr
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: check http body that matches filters
--- request
GET /hello
--- response_body
test world



=== TEST 8: filter substitute global
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: check http body that substitute global
--- request
GET /hello
--- response_body
hetto wortd



=== TEST 10: filter replace with empty
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: check http body that replace with empty
--- request
GET /hello
--- response_body
 world



=== TEST 12: filter replace with words
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: check http body that replace with words
--- request
GET /hello
--- response_body
hello *



=== TEST 14: set body and filters(body no effect)
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
                            "body": "new body",
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "HELLO"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: check http body that set body and filters
--- request
GET /hello
--- response_body
HELLO world



=== TEST 16: set multiple filters
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 17: check http body that set multiple filters
--- request
GET /hello
--- response_body
HETLO world



=== TEST 18: filters no any match
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 19: check http body that filters no any match
--- request
GET /hello
--- response_body
hello world
