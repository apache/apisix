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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.basic-auth")
            local ok, err = plugin.check_schema({username = 'foo', password = 'bar'})
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



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.basic-auth")
            local ok, err = plugin.check_schema({username = 123, password = "bar"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "username" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "foo",
                            "plugins": {
                                "basic-auth": {
                                    "username": "foo",
                                    "password": "bar"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 6: verify, invalid username
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Invalid user key in authorization"}
--- no_error_log
[error]



=== TEST 7: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Password is error"}
--- no_error_log
[error]



=== TEST 8: verify
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- no_error_log
[error]

