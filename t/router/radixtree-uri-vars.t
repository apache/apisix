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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(id: 1) with vars(user_agent ~* android)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["http_user_agent", "~*", "android"]]
                }]=]
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
--- no_error_log
[error]



=== TEST 2: not found because user_agent=ios
--- request
GET /hello
--- more_headers
User-Agent: ios
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 3: hit routes with user_agent=android
--- request
GET /hello
--- more_headers
User-Agent: android
--- response_body
hello world
--- no_error_log
[error]



=== TEST 4: hit routes with user_agent=Android
--- request
GET /hello
--- more_headers
User-Agent: Android
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: set route(id: 1) with vars(user_agent ! ~* android)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["http_user_agent", "!", "~*", "android"]]
                }]=]
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
--- no_error_log
[error]



=== TEST 6: not found because user_agent=android
--- request
GET /hello
--- more_headers
User-Agent: android
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 7: hit routes with user_agent=ios
--- request
GET /hello
--- more_headers
User-Agent: ios
--- response_body
hello world
--- no_error_log
[error]



=== TEST 8: set route(id: 1) with vars(in table)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["http_user_agent", "IN", ["android", "ios"]]]
                }]=]
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
--- no_error_log
[error]



=== TEST 9: hit routes with user_agent=ios
--- request
GET /hello
--- more_headers
User-Agent: ios
--- response_body
hello world
--- no_error_log
[error]



=== TEST 10: hit routes with user_agent=android
--- request
GET /hello
--- more_headers
User-Agent: android
--- response_body
hello world
--- no_error_log
[error]



=== TEST 11: set route(id: 1) with vars(null)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["http_user_agent", "==", null]]
                }]=]
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
--- no_error_log
[error]



=== TEST 12: not found because user_agent=android
--- request
GET /hello
--- more_headers
User-Agent: android
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 13: hit route
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 14: set route(id: 1) with vars(items are two)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- deprecated, will be removed soon
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["http_user_agent", "ios"]]
                }]=]
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
--- no_error_log
[error]



=== TEST 15: hit routes with user_agent=ios
--- request
GET /hello
--- more_headers
User-Agent: ios
--- response_body
hello world
--- no_error_log
[error]



=== TEST 16: vars rule with logical operator (set)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [
                            "!OR",
                            ["http_user_agent", "==", "ios"],
                            ["http_demo", "==", "test"]
                        ]
                }]=]
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
--- no_error_log
[error]



=== TEST 17: vars rule with logical operator (hit)
--- request
GET /hello
--- more_headers
User-Agent: android
demo: prod
--- response_body
hello world
--- no_error_log
[error]



=== TEST 18: vars rule with logical operator (miss)
--- request
GET /hello
--- more_headers
User-Agent: ios
demo: prod
--- error_code: 404
--- no_error_log
[error]



=== TEST 19: be compatible with empty vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": []
                }]=]
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
--- no_error_log
[error]



=== TEST 20: hit
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 21: bad vars rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": ["http_user_agent", "~*", "android"]
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to validate the 'vars' expression: rule should be wrapped inside brackets"}
--- no_error_log
[error]
