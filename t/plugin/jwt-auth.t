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



=== TEST 24: enable jwt auth plugin with extra field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "key": "123"
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
--- error_code: 400
--- response_body_like
\{"error_msg":"failed to check the configuration of plugin jwt-auth err: additional properties forbidden, found key"\}
--- no_error_log
[error]



=== TEST 25: get the schema by schema_type
--- request
GET /apisix/admin/schema/plugins/jwt-auth?schema_type=consumer
--- response_body
{"required":["key"],"properties":{"exp":{"minimum":1,"type":"integer"},"private_key":{"type":"string"},"public_key":{"type":"string"},"algorithm":{"type":"string","default":"HS256","enum":["HS256","HS512","RS256"]},"base64_secret":{"default":false,"type":"boolean"},"secret":{"type":"string"},"key":{"type":"string"}},"additionalProperties":false,"type":"object"}
--- no_error_log
[error]



=== TEST 26: get the schema by error schema_type
--- request
GET /apisix/admin/schema/plugins/jwt-auth?schema_type=consumer123123
--- response_body
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
--- no_error_log
[error]



=== TEST 27: get the schema by default schema_type
--- request
GET /apisix/admin/schema/plugins/jwt-auth
--- response_body
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
--- no_error_log
[error]



=== TEST 28: add consumer with username and plugins with public_key, private_key(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                            "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "kerouac",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-rs256",
                                    "algorithm": "RS256",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
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



=== TEST 29: JWT sign and verify use RS256 algorithm(private_key numbits = 512)
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



=== TEST 30: sign use RS256 algorithm(private_key numbits = 512)
--- request
GET /apisix/plugin/jwt/sign?key=user-key-rs256
--- response_body_like eval
qr/eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Gd3dEUVlKS29aSWh2Y05BUUVCQlFBRFN3QXdTQUpCQUtlYkR4bHZRTUd5RWVzQUwxcjFuSUpCa1NkcXUzSHJcbjdub3FcLzB1a2lacVZRTFNKUE1PdjBveFFTdXR2dkszaG9pYndHYWtET3phK3hSSVRCN2NzMmNFQ0F3RUFBUT09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwiYWxnIjoiUlMyNTYiLCJ0eXAiOiJKV1QifQ.\w+.\w+/
--- no_error_log
[error]



=== TEST 31: verify (in argument) use RS256 algorithm(private_key numbits = 512)
--- request
GET /hello?jwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Gd3dEUVlKS29aSWh2Y05BUUVCQlFBRFN3QXdTQUpCQUtlYkR4bHZRTUd5RWVzQUwxcjFuSUpCa1NkcXUzSHJcbjdub3FcLzB1a2lacVZRTFNKUE1PdjBveFFTdXR2dkszaG9pYndHYWtET3phK3hSSVRCN2NzMmNFQ0F3RUFBUT09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwiYWxnIjoiUlMyNTYiLCJ0eXAiOiJKV1QifQ.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsImV4cCI6MTkxOTY5Mjg3OX0.S7XMbZjl3HAm_r9xlXaKGnvQgMA6-G9RZ-3esJM3B3gDuTeyPr_JvWzou-9aDVCArr0ogcSa2dx7EwiwKaOwIA
--- response_body
hello world
--- no_error_log
[error]



=== TEST 32: add consumer with username and plugins with public_key, private_key(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----",
                            ]] .. [[
                            "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
                            }
                        }
                    }
                ]],
                [[{
                    "node": {
                        "value": {
                            "username": "kerouac",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-rs256",
                                    "algorithm": "RS256",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----",
                                    ]] .. [[
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
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



=== TEST 33: JWT sign and verify use RS256 algorithm(private_key numbits = 1024)
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



=== TEST 34: sign use RS256 algorithm(private_key numbits = 1024)
--- request
GET /apisix/plugin/jwt/sign?key=user-key-rs256
--- response_body_like eval
qr/eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JR2ZNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0R05BRENCaVFLQmdRREd4T2ZWZVwvc2VQNVRcL1Y4cGtTNVlOQVBSQ1xuM0ZmeHhlZGk3djBweVpoXC80ZDRwOVF4MFA5d09tQUx3bE9xNEZ0Z2tzMzExcHhHMHpMMExjVEpZNGlrYmMzcjBcbmg4U00weWhqOVVWMVZHdHVpYTRZYWtvYnZwTTlVK2txM2x5SU1POVpQUmV6MGNQM0FKSVlDdDV5ZjhFN2JOWUpcbmpiSk5qbDhXeHZNMXRESHFWUUlEQVFBQlxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sImFsZyI6IlJTMjU2IiwidHlwIjoiSldUIn0.\w+.\w+/
--- no_error_log
[error]



=== TEST 35: verify (in argument) use RS256 algorithm(private_key numbits = 1024)
--- request
GET /hello?jwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JR2ZNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0R05BRENCaVFLQmdRREd4T2ZWZVwvc2VQNVRcL1Y4cGtTNVlOQVBSQ1xuM0ZmeHhlZGk3djBweVpoXC80ZDRwOVF4MFA5d09tQUx3bE9xNEZ0Z2tzMzExcHhHMHpMMExjVEpZNGlrYmMzcjBcbmg4U00weWhqOVVWMVZHdHVpYTRZYWtvYnZwTTlVK2txM2x5SU1POVpQUmV6MGNQM0FKSVlDdDV5ZjhFN2JOWUpcbmpiSk5qbDhXeHZNMXRESHFWUUlEQVFBQlxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sImFsZyI6IlJTMjU2IiwidHlwIjoiSldUIn0.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsImV4cCI6MTkxOTc4MjQ0MH0.ExLbD7bMUw4117DTXwdxOJ2cfJajSX0VzINkKzjvr7-4sod9q2gpLbemoXH_IBIcdKF2raC8k6OVxRUAJa_Nlk4NIdbjEWk4Z9zfdjWK_t7QED-5nfoYflwGVOpNh-q8zdXsZRhPnBWuPB9yGJLpI_NfqdRdlRQrQ3JaCIgvYBg
--- response_body
hello world
--- no_error_log
[error]



=== TEST 36: add consumer with username and plugins with public_key, private_key(private_key numbits = 2048)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv5LHjZ4FxQ9jk6eQGDRt\noRwFVkLq+dUBebs97hrzirokVr2B+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6\nnWSqTQpWbQ8c7CrF31EkIHUYRzZvWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqx\nnj9npDqKrMODOENy31SqZNerWZsdgGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4\nNaxnnzcvll4yqwrBELSeDZEAt0+e/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5Ex\ntLHXVzgx752PHMwmuj9mO1ko6p8FOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U\n8wIDAQAB\n-----END PUBLIC KEY-----",
                            ]] .. [[
                            "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAv5LHjZ4FxQ9jk6eQGDRtoRwFVkLq+dUBebs97hrzirokVr2B\n+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6nWSqTQpWbQ8c7CrF31EkIHUYRzZv\nWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqxnj9npDqKrMODOENy31SqZNerWZsd\ngGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4Naxnnzcvll4yqwrBELSeDZEAt0+e\n/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5ExtLHXVzgx752PHMwmuj9mO1ko6p8F\nOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U8wIDAQABAoIBAFsFQC73H8KrNyKW\ngI4fit77U0XS8ZXWMKdH4XrZ71DAdDeKPtC+M05+1GxMbhAeEl8WXraTQ8J0G2s1\nMtXqEMDrbUbBXKLghVtoTy91e/a369sZ7/qgN19Eq/30WzWdDIGhVZgwcy2Xd8hw\nitZIPi/z7ChJcE35bsUytseJkJPsWeMJNq4mLbHqMSBQWze/vNvIeGYr2xfqXc6H\nywGWGlk46RI28mOf7PecU0DxFoTBNcntZrpOwaIrTDsC7E6uNvhVbtsneseTlQuj\nihS7DAH72Zx3CXc9+SL3b5QNRD1Rnp+gKM6itjW1yduOj2dS0p8YzcUYNtxnw5Gv\nuLoHwuECgYEA58NhvnHn10YLBEMYxb30tDobdGfOjBSfih8K53+/SJhqF5mv4qZX\nUfw3o5R+CkkrhbZ24yst7wqKFYZ+LfazOqljOPOrBsgIIry/sXBlcbGLCw9MYFfB\nejKTt/xZjqLdDCcEbiSB0L2xNuyF/TZOu8V5Nu55LXKBqeW4yISQ5FkCgYEA05t1\n2cq8gE1jMfGXQNFIpUDG2j4wJXAPqnJZSUF/BICa55mH/HYRKoP2uTSvAnqNrdGt\nsnjnnMA7T+fGogB4STif1POWfj+BTKVa/qhUX9ytH6TeI4aqPXSZdTVEPRfR7bG1\nIB/j2lyPkiNi2VijMx33xqxIaQUUsvxIT95GSisCgYAdaJFylQmSK3UiaVEvZlcy\nt1zcfH+dDtDfueisT216TLzJmdrTq7/Qy2xT+Xe03mwDX4/ea5A8kN3MtXA1bOR5\nQR0yENlW1vMRVVoNrfFxZ9H46UwLvZbzZo+P/RlwHAJolFrfjwpZ7ngaPBEUfFup\nP/mNmt0Ng0YoxNmZuBiaoQKBgQCa2d4RRgpRvdAEYW41UbHetJuQZAfprarZKZrr\nP9HKoq45I6Je/qurOCzZ9ZLItpRtic6Zl16u2AHPhKZYMQ3VT2mvdZ5AvwpI44zG\nZLpx+FR8nrKsvsRf+q6+Ff/c0Uyfq/cHDi84wZmS8PBKa1Hqe1ix+6t1pvEx1eq4\n/8jiRwKBgGOZzt5H5P0v3cFG9EUPXtvf2k81GmZjlDWu1gu5yWSYpqCfYr/K/1Md\ndaQ/YCKTc12SYL7hZ2j+2/dGFXNXwknIyKNj76UxjUpJywWI5mUaXJZJDkLCRvxF\nkk9nWvPorpjjjxaIVN+TkGgDd/60at/tI6HxzZitVyla5rB8hoPm\n-----END RSA PRIVATE KEY-----"
                            }
                        }
                    }
                ]],
                [[{
                    "node": {
                        "value": {
                            "username": "kerouac",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-rs256",
                                    "algorithm": "RS256",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv5LHjZ4FxQ9jk6eQGDRt\noRwFVkLq+dUBebs97hrzirokVr2B+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6\nnWSqTQpWbQ8c7CrF31EkIHUYRzZvWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqx\nnj9npDqKrMODOENy31SqZNerWZsdgGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4\nNaxnnzcvll4yqwrBELSeDZEAt0+e/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5Ex\ntLHXVzgx752PHMwmuj9mO1ko6p8FOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U\n8wIDAQAB\n-----END PUBLIC KEY-----",
                                    ]] .. [[
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAv5LHjZ4FxQ9jk6eQGDRtoRwFVkLq+dUBebs97hrzirokVr2B\n+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6nWSqTQpWbQ8c7CrF31EkIHUYRzZv\nWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqxnj9npDqKrMODOENy31SqZNerWZsd\ngGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4Naxnnzcvll4yqwrBELSeDZEAt0+e\n/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5ExtLHXVzgx752PHMwmuj9mO1ko6p8F\nOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U8wIDAQABAoIBAFsFQC73H8KrNyKW\ngI4fit77U0XS8ZXWMKdH4XrZ71DAdDeKPtC+M05+1GxMbhAeEl8WXraTQ8J0G2s1\nMtXqEMDrbUbBXKLghVtoTy91e/a369sZ7/qgN19Eq/30WzWdDIGhVZgwcy2Xd8hw\nitZIPi/z7ChJcE35bsUytseJkJPsWeMJNq4mLbHqMSBQWze/vNvIeGYr2xfqXc6H\nywGWGlk46RI28mOf7PecU0DxFoTBNcntZrpOwaIrTDsC7E6uNvhVbtsneseTlQuj\nihS7DAH72Zx3CXc9+SL3b5QNRD1Rnp+gKM6itjW1yduOj2dS0p8YzcUYNtxnw5Gv\nuLoHwuECgYEA58NhvnHn10YLBEMYxb30tDobdGfOjBSfih8K53+/SJhqF5mv4qZX\nUfw3o5R+CkkrhbZ24yst7wqKFYZ+LfazOqljOPOrBsgIIry/sXBlcbGLCw9MYFfB\nejKTt/xZjqLdDCcEbiSB0L2xNuyF/TZOu8V5Nu55LXKBqeW4yISQ5FkCgYEA05t1\n2cq8gE1jMfGXQNFIpUDG2j4wJXAPqnJZSUF/BICa55mH/HYRKoP2uTSvAnqNrdGt\nsnjnnMA7T+fGogB4STif1POWfj+BTKVa/qhUX9ytH6TeI4aqPXSZdTVEPRfR7bG1\nIB/j2lyPkiNi2VijMx33xqxIaQUUsvxIT95GSisCgYAdaJFylQmSK3UiaVEvZlcy\nt1zcfH+dDtDfueisT216TLzJmdrTq7/Qy2xT+Xe03mwDX4/ea5A8kN3MtXA1bOR5\nQR0yENlW1vMRVVoNrfFxZ9H46UwLvZbzZo+P/RlwHAJolFrfjwpZ7ngaPBEUfFup\nP/mNmt0Ng0YoxNmZuBiaoQKBgQCa2d4RRgpRvdAEYW41UbHetJuQZAfprarZKZrr\nP9HKoq45I6Je/qurOCzZ9ZLItpRtic6Zl16u2AHPhKZYMQ3VT2mvdZ5AvwpI44zG\nZLpx+FR8nrKsvsRf+q6+Ff/c0Uyfq/cHDi84wZmS8PBKa1Hqe1ix+6t1pvEx1eq4\n/8jiRwKBgGOZzt5H5P0v3cFG9EUPXtvf2k81GmZjlDWu1gu5yWSYpqCfYr/K/1Md\ndaQ/YCKTc12SYL7hZ2j+2/dGFXNXwknIyKNj76UxjUpJywWI5mUaXJZJDkLCRvxF\nkk9nWvPorpjjjxaIVN+TkGgDd/60at/tI6HxzZitVyla5rB8hoPm\n-----END RSA PRIVATE KEY-----"
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



=== TEST 37: JWT sign and verify use RS256 algorithm(private_key numbits = 2048)
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



=== TEST 38: sign use RS256 algorithm(private_key numbits = 2048)
--- request
GET /apisix/plugin/jwt/sign?key=user-key-rs256
--- response_body_like eval
qr/eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBdjVMSGpaNEZ4UTlqazZlUUdEUnRcbm9Sd0ZWa0xxK2RVQmViczk3aHJ6aXJva1ZyMkIrUm94cWRMZktBTStBc04yRGFkYXdaMkdxbENWOURMMFwvZ3o2XG5uV1NxVFFwV2JROGM3Q3JGMzFFa0lIVVlSelp2V3kxN0szV0M5T2RrXC9nTTFGVmQwSGJaMlJqdXFqOUFEZWVxeFxubmo5bnBEcUtyTU9ET0VOeTMxU3FaTmVyV1pzZGdHa01MNUpZYlg1aGJJMkw5TFJFdlJVMjFmRGdTZkdMNk13NFxuTmF4bm56Y3ZsbDR5cXdyQkVMU2VEWkVBdDArZVwvcDFkTzdtb3hGK2IxcEZraDl2UWw2ekd2bnZmOGZPcW41RXhcbnRMSFhWemd4NzUyUEhNd211ajltTzFrbzZwOEZPTTBKSERub29JKzVyd0s0ajNJMjdIbzVubmF0VldVYXhLNFVcbjh3SURBUUFCXG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwiYWxnIjoiUlMyNTYiLCJ0eXAiOiJKV1QifQ.\w+.\w+/
--- no_error_log
[error]



=== TEST 39: verify (in argument) use RS256 algorithm(private_key numbits = 2048)
--- request
GET /hello?jwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBdjVMSGpaNEZ4UTlqazZlUUdEUnRcbm9Sd0ZWa0xxK2RVQmViczk3aHJ6aXJva1ZyMkIrUm94cWRMZktBTStBc04yRGFkYXdaMkdxbENWOURMMFwvZ3o2XG5uV1NxVFFwV2JROGM3Q3JGMzFFa0lIVVlSelp2V3kxN0szV0M5T2RrXC9nTTFGVmQwSGJaMlJqdXFqOUFEZWVxeFxubmo5bnBEcUtyTU9ET0VOeTMxU3FaTmVyV1pzZGdHa01MNUpZYlg1aGJJMkw5TFJFdlJVMjFmRGdTZkdMNk13NFxuTmF4bm56Y3ZsbDR5cXdyQkVMU2VEWkVBdDArZVwvcDFkTzdtb3hGK2IxcEZraDl2UWw2ekd2bnZmOGZPcW41RXhcbnRMSFhWemd4NzUyUEhNd211ajltTzFrbzZwOEZPTTBKSERub29JKzVyd0s0ajNJMjdIbzVubmF0VldVYXhLNFVcbjh3SURBUUFCXG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwiYWxnIjoiUlMyNTYiLCJ0eXAiOiJKV1QifQ.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsImV4cCI6MTkxOTc3MTQ3Mn0.m8n0iq0FthBGuCP4IOzIi9J0aHJeBKGhV0A7_DI0QqdXDxFjImGZSsDrNa77_3_gQonLY9xwWO0eobBzcpXuBQKVjl7fEn1brY4m1SKMB0xxWn525khzWe4aN3Yf101fCXd-8rKfZoCOMs_KS9YLTpEGbHJJ3nPiJdN9Btlt-jqCfbQvTT_zogITxJBcUiwz_ikttDTCLVrAvE5M7Xmck245MayOhSvu0f1df1XcmdrnKV4fHypl3UPhQNdb0Up4IBao0lJsKF2QCrvn_rP_oXrViurnpJDv6nP_46woWvnS74_WWGmVg2BptlQ7p8IYF4yAoXW8gsjcgoixbYTOGg
--- response_body
hello world
--- no_error_log
[error]



=== TEST 40: JWT sign with the public key when using the RS256 algorithm
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "private_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                            "public_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "kerouac",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-rs256",
                                    "algorithm": "RS256",
                                    "private_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                                    "public_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
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



=== TEST 41: JWT sign and verify RS256
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



=== TEST 42: sign failed
--- request
GET /apisix/plugin/jwt/sign?key=user-key-rs256
--- error_code: 500
--- response_body eval
qr/failed to sign jwt/



=== TEST 43: sanity(algorithm = HS512)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {key = "123", algorithm = "HS512"}

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
qr/{"algorithm":"HS512","secret":"[a-zA-Z0-9+\\\/]+={0,2}","key":"123","exp":86400}/
--- no_error_log
[error]



=== TEST 44: add consumer with username and plugins use HS512 algorithm
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-HS512",
                            "algorithm": "HS512",
                            "secret": "my-secret-key"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "kerouac",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-HS512",
                                    "algorithm": "HS512",
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



=== TEST 45: JWT sign and verify use HS512 algorithm
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



=== TEST 46: sign(algorithm = HS512)
--- request
GET /apisix/plugin/jwt/sign?key=user-key-HS512
--- response_body_like eval
qr/eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.\w+.\w+/
--- no_error_log
[error]



=== TEST 47: verify (in argument) use HS512 algorithm
--- request
GET /hello?jwt=eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1IUzUxMiIsImV4cCI6MTkxOTc4NzU5OH0.zJAE-BDs6QtMvGbBmQL6hNbZ9seYSfZ9SDH3R3VSiOhY3UAjdrl3SUStTeCirlVzIV1eoEiW2jd_xHpKNw7nWA
--- response_body
hello world
--- no_error_log
[error]



=== TEST 48: test for unsupported algorithm
--- request
PATCH /apisix/plugin/jwt/sign?key=user-key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {key = "123", algorithm = "ES256"}

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
qr/property "algorithm" validation failed/
