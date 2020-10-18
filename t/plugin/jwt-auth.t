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
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {key = "123"}

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/{"algorithm":"HS256","secret":"[a-zA-Z0-9+\\\/]+={0,2}","key":"123","exp":86400}/
--- no_error_log
[error]



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwt-auth")
            local ok, err = plugin.check_schema({key = 123}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "key" validation failed: wrong type: expected string, got number
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
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key",
                                    "secret": "my-secret-key"
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



=== TEST 4: enable jwt auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
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



=== TEST 5: sign
--- request
GET /apisix/plugin/jwt/sign?key=user-key
--- response_body_like eval
qr/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.\w+.\w+/
--- no_error_log
[error]



=== TEST 6: test for unsupported method
--- request
PATCH /apisix/plugin/jwt/sign?key=user-key
--- error_code: 404



=== TEST 7: verify, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing JWT token in request"}
--- no_error_log
[error]



=== TEST 8: verify: invalid JWT token
--- request
GET /hello?jwt=invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"}
--- no_error_log
[error]



=== TEST 9: verify: expired JWT token
--- request
GET /hello?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"'exp' claim expired at Tue, 23 Jul 2019 08:28:21 GMT"}
--- no_error_log
[error]



=== TEST 10: verify (in argument)
--- request
GET /hello?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
[error]



=== TEST 11: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
[error]



=== TEST 12: verify (in cookie)
--- request
GET /hello
--- more_headers
Cookie: jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
[error]



=== TEST 13: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
[error]



=== TEST 14: verify (header with bearer)
--- request
GET /hello
--- more_headers
Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- no_error_log
[error]



=== TEST 15: verify (invalid bearer token)
--- request
GET /hello
--- more_headers
Authorization: bearer invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- error_code: 401
--- response_body
{"message":"invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"}
--- no_error_log
[error]



=== TEST 16: delete a exist consumer
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)

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
            ngx.say("code: ", code < 300, " body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "chen",
                    "plugins": {
                        "jwt-auth": {
                            "key": "chen-key",
                            "secret": "chen-key"
                        }
                    }
                }]]
            )
            ngx.say("code: ", code < 300, " body: ", body)

            code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, " body: ", body)

            ngx.sleep(1)
            code, body = t('/apisix/plugin/jwt/sign?key=chen-key',
                ngx.HTTP_GET)
            ngx.say("code: ", code < 300, " body: ", body)
        }
    }
--- request
GET /t
--- response_body
code: true body: passed
code: true body: passed
code: true body: passed
code: true body: passed
--- no_error_log
[error]



=== TEST 17: add consumer with username and plugins with base64 secret
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
                            "secret": "fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=",
                            "base64_secret": true
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key",
                                    "secret": "fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=",
                                    "base64_secret": true
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



=== TEST 18: enable jwt auth plugin with base64 secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
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



=== TEST 19: sign
--- request
GET /apisix/plugin/jwt/sign?key=user-key
--- response_body_like eval
qr/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.\w+.\w+/
--- no_error_log
[error]



=== TEST 20: verify: invalid JWT token
--- request
GET /hello?jwt=invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"}
--- no_error_log
[error]



=== TEST 21: verify: invalid signature
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- error_code: 401
--- response_body
{"message":"signature mismatch: fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs"}
--- no_error_log
[error]



=== TEST 22: verify: happy path
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0._kNmXeH1uYVAvApFTONk2Z3Gh-a4XfGrjmqd_ahoOI0
--- response_body
hello world
--- no_error_log
[error]



=== TEST 23: without key
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwt-auth")
            local ok, err = plugin.check_schema({}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "key" is required
--- no_error_log
[error]
