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
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(only arg_k)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "vars": [ ["arg_k", "==", "v"] ],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 3: /not_found
--- request
GET /hello?k=not-hit
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 4: hit routes
--- request
GET /hello?k=v
--- response_body
hello world



=== TEST 5: set route(cookie)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "vars": [["cookie_k", "==", "v"]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 6: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 7: /not_found
--- more_headers
Cookie: k=not-hit; kkk=vvv;
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 8: hit routes
--- more_headers
Cookie: k=v; kkk=vvv;
--- request
GET /hello
--- response_body
hello world



=== TEST 9: set route(header)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "vars": [["http_k", "==", "v"]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 10: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 11: /not_found
--- more_headers
k: not-hit
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 12: hit routes
--- more_headers
k: v
--- request
GET /hello
--- response_body
hello world



=== TEST 13: set route(uri arg + header + cookie)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "vars": [["http_k", "==", "header"], ["cookie_k", "==", "cookie"], ["arg_k", "==", "uri_arg"]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 14: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 15: /not_found
--- more_headers
k: header
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 16: hit routes
--- more_headers
Cookie: k=cookie
k: header
--- request
GET /hello?k=uri_arg
--- response_body
hello world



=== TEST 17: set route(only post arg)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "vars": [["post_arg_k", "==", "post_form"]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 18: not_found (GET request)
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 19: not_found (wrong request body)
--- request
POST /hello
123
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 20: not_found (wrong content type)
--- request
POST /hello
k=post_form
--- more_headers
Content-Type: multipart/form-data
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 21: hit routes
--- request
POST /hello
k=post_form
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- response_body
hello world
