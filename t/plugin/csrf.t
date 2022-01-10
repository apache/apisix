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

no_long_string();
no_shuffle();
no_root_location();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.csrf")
            local ok, err = plugin.check_schema({name = '_csrf', expires = 3600, key = 'testkey'})
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



=== TEST 2: set csrf plugin
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
                        "csrf": {
                            "key": "userkey"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: have csrf cookie
--- request
GET /hello
--- response_header
Set-Cookie



=== TEST4: block request
--- request
POST /hello
--- error_code: 401
--- response_body
{"error_msg":"no csrf token in headers"}
--- no_error_log
[error]



=== TEST5: only header
--- request
POST /hello
--- more_headers
apisix-csrf-token: wrongtoken
--- error_code: 401
--- response_body
{"error_msg":"no csrf cookie"}
--- no_error_log
[error]



=== TEST6: only cookie
--- request
POST /hello
--- more_headers
Cookie: apisix-csrf-token=testcookie
--- error_code: 401
--- response_body
{"error_msg":"no csrf token in headers"}
--- no_error_log
[error]



=== TEST7: header and cookie mismatch
--- request
POST /hello
--- more_headers
apisix-csrf-token: wrongtoken
Cookie: apisix-csrf-token=testcookie
--- error_code: 401
--- response_body
{"error_msg":"csrf token mismatch"}
--- no_error_log
[error]



=== TEST8: invalid csrf token
--- request
POST /hello
--- more_headers
apisix-csrf-token: eyJleHBpcmVzIjo3MjAwLCJyYW5kb20iOjAuMjE2ODAxOTYyNTEwNDEsInNpZ24iOiJqZnhDckk1TVwvMHI3VjdyWWRBSXNCeEg3emljY3VnV0dySGtYQkZ0QT0ifQ==
Cookie: apisix-csrf-token=eyJleHBpcmVzIjo3MjAwLCJyYW5kb20iOjAuMjE2ODAxOTYyNTEwNDEsInNpZ24iOiJqZnhDckk1TVwvMHI3VjdyWWRBSXNCeEg3emljY3VnV0dySGtYQkZ0QT0ifQ==
--- error_code: 401
--- response_body
{"error_msg":"Failed to verify the csrf token signature"}
