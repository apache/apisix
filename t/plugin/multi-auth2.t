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
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: add consumer with basic-auth and key-auth plugins
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
                        },
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
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



=== TEST 2: enable multi auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "jwt-auth": {}
                                },
                                {
                                    "hmac-auth": {}
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
--- request
GET /t
--- response_body
passed



=== TEST 5: invalid basic-auth credentials
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- error_log
basic-auth failed to authenticate the request, code: 401. error: Invalid user authorization
jwt-auth failed to authenticate the request, code: 401. error: JWT token invalid: invalid jwt string
hmac-auth failed to authenticate the request, code: 401. error: client request can't be validated: Authorization header does not start with 'Signature'



=== TEST 6: valid basic-auth creds
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- no_error_log
failed to authenticate the request



=== TEST 7: missing hmac auth authorization header
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- error_log
hmac-auth failed to authenticate the request, code: 401. error: client request can't be validated: missing Authorization header



=== TEST 8: hmac auth missing algorithm
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",headers="@request-target date" ,signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- error_log
hmac-auth failed to authenticate the request, code: 401. error: client request can't be validated: algorithm missing



=== TEST 11: add consumer with username and jwt-auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
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



=== TEST 12: test with expired jwt token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- error_log
jwt-auth failed to authenticate the request, code: 401. error: failed to verify jwt: 'exp' claim expired at Tue, 23 Jul 2019 08:28:21 GMT
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68



=== TEST 13: test with jwt token containing wrong signature
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- error_log
jwt-auth failed to authenticate the request, code: 401. error: failed to verify jwt: signature mismatch: fNtFJnNnJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNnJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs



=== TEST 14: verify jwt-auth
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
failed to authenticate the request
