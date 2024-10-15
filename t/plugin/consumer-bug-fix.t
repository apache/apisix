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
no_shuffle();
no_root_location();

run_tests;

__DATA__
=== TEST 1: add consumer jack1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "echo":{"body": "before change"}
                    }
                }]]
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
=== TEST 2: add route
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
                            "key-auth": {}
                        }
                }]]
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
=== TEST 3: verify 20 times
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- response_body eval
["before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change","before change"]
=== TEST 4: modify consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "echo":{"body": "after change"}
                    }
                }]]
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
=== TEST 5: verify 20 times
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello","GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- response_body eval
["after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change","after change"]
