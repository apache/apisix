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
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {key = "123"}

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/{"algorithm":"HS256","base64_secret":false,"exp":86400,"key":"123","lifetime_grace_period":0,"secret":"[a-zA-Z0-9+\\\/]+={0,2}"}/



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
--- response_body
property "key" validation failed: wrong type: expected string, got number
done



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
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



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
--- response_body
passed



=== TEST 5: verify, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing JWT token in request"}



=== TEST 6: verify: invalid JWT token
--- request
GET /hello?jwt=invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"JWT token invalid"}
--- error_log
JWT token invalid: invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9



=== TEST 7: verify: expired JWT token
--- request
GET /hello?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"failed to verify jwt"}
--- error_log
failed to verify jwt: 'exp' claim expired at Tue, 23 Jul 2019 08:28:21 GMT



=== TEST 8: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 9: verify (in cookie)
--- request
GET /hello
--- more_headers
Cookie: jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 10: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 11: verify (header with bearer)
--- request
GET /hello
--- more_headers
Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 12: verify (invalid bearer token)
--- request
GET /hello
--- more_headers
Authorization: bearer invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- error_code: 401
--- response_body
{"message":"JWT token invalid"}
--- error_log
JWT token invalid: invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9



=== TEST 13: delete a exist consumer
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
        }
    }
--- response_body
code: true body: passed
code: true body: passed
code: true body: passed



=== TEST 14: add consumer with username and plugins with base64 secret
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
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: enable jwt auth plugin with base64 secret
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
--- response_body
passed



=== TEST 16: sign / verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- sign is generated via https://jwt.io/#debugger-io. This is the case for all other test cases and is not specified further
            local sign = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsIm5iZiI6MTcyNzI3NDk4M30._Z8b_Asb2ROvGX4R5sNMbgJNQXB6x7aQeuVjmjY21Nw"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 17: verify: invalid JWT token
--- request
GET /hello?jwt=invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"JWT token invalid"}
--- error_log
JWT token invalid: invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9



=== TEST 18: verify: invalid signature
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- error_code: 401
--- response_body
{"message":"failed to verify jwt"}
--- error_log
failed to verify jwt: signature mismatch: fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs



=== TEST 19: verify: happy path
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0._kNmXeH1uYVAvApFTONk2Z3Gh-a4XfGrjmqd_ahoOI0
--- response_body
hello world



=== TEST 20: without key
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
--- response_body
property "key" is required



=== TEST 21: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, raw = t('/apisix/admin/schema/plugins/jwt-auth?schema_type=consumer',
                ngx.HTTP_GET,
                [[
{"dependencies":{"algorithm":{"oneOf":[{"properties":{"algorithm":{"default":"HS256","enum":["HS256","HS512"]}}},{"required":["public_key"],"properties":{"algorithm":{"enum":["RS256","ES256"]},"public_key":{"type":"string"}}}]}},"required":["key"],"type":"object","properties":{"base64_secret":{"default":false,"type":"boolean"},"secret":{"type":"string"},"algorithm":{"enum":["HS256","HS512","RS256","ES256"],"default":"HS256","type":"string"},"exp":{"minimum":1,"default":86400,"type":"integer"},"key":{"type":"string"}}}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 22: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/jwt-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
                {"properties":{},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 23: get the schema by default schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/jwt-auth',
                ngx.HTTP_GET,
                nil,
                [[
                {"properties":{},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 24: add consumer with username and plugins with public_key
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
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----"
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
--- response_body
passed
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 25: JWT sign and verify use RS256 algorithm
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
--- response_body
passed
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 26: sign/verify use RS256 algorithm(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key
            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"

            local sign = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.FaV6N-bWaSXkRrF2ec28hH5QENl-8I0LCONdNnQpB1YOb4akP-lKnwtABgfsQ_eKaEIf1PWNoghyByLejXaPbQ"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 27: add consumer with username and plugins with public_key
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
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----"
                            }
                        }
                    }
                ]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 28: JWT sign and verify use RS256 algorithm
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
--- response_body
passed
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 29: sign/verify use RS256 algorithm(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key
            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"

            local sign = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.FG-PAyscR-pFyw1a5ZiRxHLxzSI1jyVyZxm-fj3-u5igjacJY7UByCUKDnieV9-Ft81X15gdHAcrumUsTbu-77F50Bp5A1sxzdL_PXVLJ1cc8UP2ltvQwf1YWdutK7CI_uNLaeCYPZd9tWPhnfpsv4AdTdaCWeFyoaZSNOdw4oA"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 30: sign/verify use RS256 algorithm(private_key numbits = 1024,with extra payload)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key and payload
            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
            -- payload = {"aaa":"11","bb":"222"}

            local sign = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.FG-PAyscR-pFyw1a5ZiRxHLxzSI1jyVyZxm-fj3-u5igjacJY7UByCUKDnieV9-Ft81X15gdHAcrumUsTbu-77F50Bp5A1sxzdL_PXVLJ1cc8UP2ltvQwf1YWdutK7CI_uNLaeCYPZd9tWPhnfpsv4AdTdaCWeFyoaZSNOdw4oA"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 31: add consumer with username and plugins with public_key
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
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv5LHjZ4FxQ9jk6eQGDRt\noRwFVkLq+dUBebs97hrzirokVr2B+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6\nnWSqTQpWbQ8c7CrF31EkIHUYRzZvWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqx\nnj9npDqKrMODOENy31SqZNerWZsdgGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4\nNaxnnzcvll4yqwrBELSeDZEAt0+e/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5Ex\ntLHXVzgx752PHMwmuj9mO1ko6p8FOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U\n8wIDAQAB\n-----END PUBLIC KEY-----"
                            }
                        }
                    }
                ]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed
--- error_code_like: ^(?:200|201)?$



=== TEST 32: JWT sign and verify use RS256 algorithm(private_key numbits = 2048)
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
--- response_body
passed



=== TEST 33: sign/verify use RS256 algorithm(private_key numbits = 2048)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key
            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAv5LHjZ4FxQ9jk6eQGDRtoRwFVkLq+dUBebs97hrzirokVr2B\n+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6nWSqTQpWbQ8c7CrF31EkIHUYRzZv\nWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqxnj9npDqKrMODOENy31SqZNerWZsd\ngGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4Naxnnzcvll4yqwrBELSeDZEAt0+e\n/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5ExtLHXVzgx752PHMwmuj9mO1ko6p8F\nOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U8wIDAQABAoIBAFsFQC73H8KrNyKW\ngI4fit77U0XS8ZXWMKdH4XrZ71DAdDeKPtC+M05+1GxMbhAeEl8WXraTQ8J0G2s1\nMtXqEMDrbUbBXKLghVtoTy91e/a369sZ7/qgN19Eq/30WzWdDIGhVZgwcy2Xd8hw\nitZIPi/z7ChJcE35bsUytseJkJPsWeMJNq4mLbHqMSBQWze/vNvIeGYr2xfqXc6H\nywGWGlk46RI28mOf7PecU0DxFoTBNcntZrpOwaIrTDsC7E6uNvhVbtsneseTlQuj\nihS7DAH72Zx3CXc9+SL3b5QNRD1Rnp+gKM6itjW1yduOj2dS0p8YzcUYNtxnw5Gv\nuLoHwuECgYEA58NhvnHn10YLBEMYxb30tDobdGfOjBSfih8K53+/SJhqF5mv4qZX\nUfw3o5R+CkkrhbZ24yst7wqKFYZ+LfazOqljOPOrBsgIIry/sXBlcbGLCw9MYFfB\nejKTt/xZjqLdDCcEbiSB0L2xNuyF/TZOu8V5Nu55LXKBqeW4yISQ5FkCgYEA05t1\n2cq8gE1jMfGXQNFIpUDG2j4wJXAPqnJZSUF/BICa55mH/HYRKoP2uTSvAnqNrdGt\nsnjnnMA7T+fGogB4STif1POWfj+BTKVa/qhUX9ytH6TeI4aqPXSZdTVEPRfR7bG1\nIB/j2lyPkiNi2VijMx33xqxIaQUUsvxIT95GSisCgYAdaJFylQmSK3UiaVEvZlcy\nt1zcfH+dDtDfueisT216TLzJmdrTq7/Qy2xT+Xe03mwDX4/ea5A8kN3MtXA1bOR5\nQR0yENlW1vMRVVoNrfFxZ9H46UwLvZbzZo+P/RlwHAJolFrfjwpZ7ngaPBEUfFup\nP/mNmt0Ng0YoxNmZuBiaoQKBgQCa2d4RRgpRvdAEYW41UbHetJuQZAfprarZKZrr\nP9HKoq45I6Je/qurOCzZ9ZLItpRtic6Zl16u2AHPhKZYMQ3VT2mvdZ5AvwpI44zG\nZLpx+FR8nrKsvsRf+q6+Ff/c0Uyfq/cHDi84wZmS8PBKa1Hqe1ix+6t1pvEx1eq4\n/8jiRwKBgGOZzt5H5P0v3cFG9EUPXtvf2k81GmZjlDWu1gu5yWSYpqCfYr/K/1Md\ndaQ/YCKTc12SYL7hZ2j+2/dGFXNXwknIyKNj76UxjUpJywWI5mUaXJZJDkLCRvxF\nkk9nWvPorpjjjxaIVN+TkGgDd/60at/tI6HxzZitVyla5rB8hoPm\n-----END RSA PRIVATE KEY-----"

            local sign = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.Zvp8dXefvGXrKgeoaNsA3sbV_3fw1w6Te7a0B_UANzef7gGJwvlnD6c3-f4yAy7GPgNzP_H1-atcF-sgLHAYpUa14XKe22a9S_BJSoQszoZuqGgpnGcjSzDMK9JX3FLUtzOFMQR5C4_3d7_z0NlepNo2xdQ6IQj0SvS1jrNwydpA9L89N07id3EO739uNw339g78N9QHP-j8nWItfbjo31xefCWTHtcloGkfaJOhcr06qmSbrivBU1AuPA8T3ZVumqw6fcRJzrvQJdKEfVyP-IPUtUy8SM1yLqstaKojJtU3A2HKaeb4fycwHXxtl52xhzIshr_I3iUhX_ak-z7m0A"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 34: sign/verify use RS256 algorithm(private_key numbits = 2048,with extra payload)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key and payload
            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAv5LHjZ4FxQ9jk6eQGDRtoRwFVkLq+dUBebs97hrzirokVr2B\n+RoxqdLfKAM+AsN2DadawZ2GqlCV9DL0/gz6nWSqTQpWbQ8c7CrF31EkIHUYRzZv\nWy17K3WC9Odk/gM1FVd0HbZ2Rjuqj9ADeeqxnj9npDqKrMODOENy31SqZNerWZsd\ngGkML5JYbX5hbI2L9LREvRU21fDgSfGL6Mw4Naxnnzcvll4yqwrBELSeDZEAt0+e\n/p1dO7moxF+b1pFkh9vQl6zGvnvf8fOqn5ExtLHXVzgx752PHMwmuj9mO1ko6p8F\nOM0JHDnooI+5rwK4j3I27Ho5nnatVWUaxK4U8wIDAQABAoIBAFsFQC73H8KrNyKW\ngI4fit77U0XS8ZXWMKdH4XrZ71DAdDeKPtC+M05+1GxMbhAeEl8WXraTQ8J0G2s1\nMtXqEMDrbUbBXKLghVtoTy91e/a369sZ7/qgN19Eq/30WzWdDIGhVZgwcy2Xd8hw\nitZIPi/z7ChJcE35bsUytseJkJPsWeMJNq4mLbHqMSBQWze/vNvIeGYr2xfqXc6H\nywGWGlk46RI28mOf7PecU0DxFoTBNcntZrpOwaIrTDsC7E6uNvhVbtsneseTlQuj\nihS7DAH72Zx3CXc9+SL3b5QNRD1Rnp+gKM6itjW1yduOj2dS0p8YzcUYNtxnw5Gv\nuLoHwuECgYEA58NhvnHn10YLBEMYxb30tDobdGfOjBSfih8K53+/SJhqF5mv4qZX\nUfw3o5R+CkkrhbZ24yst7wqKFYZ+LfazOqljOPOrBsgIIry/sXBlcbGLCw9MYFfB\nejKTt/xZjqLdDCcEbiSB0L2xNuyF/TZOu8V5Nu55LXKBqeW4yISQ5FkCgYEA05t1\n2cq8gE1jMfGXQNFIpUDG2j4wJXAPqnJZSUF/BICa55mH/HYRKoP2uTSvAnqNrdGt\nsnjnnMA7T+fGogB4STif1POWfj+BTKVa/qhUX9ytH6TeI4aqPXSZdTVEPRfR7bG1\nIB/j2lyPkiNi2VijMx33xqxIaQUUsvxIT95GSisCgYAdaJFylQmSK3UiaVEvZlcy\nt1zcfH+dDtDfueisT216TLzJmdrTq7/Qy2xT+Xe03mwDX4/ea5A8kN3MtXA1bOR5\nQR0yENlW1vMRVVoNrfFxZ9H46UwLvZbzZo+P/RlwHAJolFrfjwpZ7ngaPBEUfFup\nP/mNmt0Ng0YoxNmZuBiaoQKBgQCa2d4RRgpRvdAEYW41UbHetJuQZAfprarZKZrr\nP9HKoq45I6Je/qurOCzZ9ZLItpRtic6Zl16u2AHPhKZYMQ3VT2mvdZ5AvwpI44zG\nZLpx+FR8nrKsvsRf+q6+Ff/c0Uyfq/cHDi84wZmS8PBKa1Hqe1ix+6t1pvEx1eq4\n/8jiRwKBgGOZzt5H5P0v3cFG9EUPXtvf2k81GmZjlDWu1gu5yWSYpqCfYr/K/1Md\ndaQ/YCKTc12SYL7hZ2j+2/dGFXNXwknIyKNj76UxjUpJywWI5mUaXJZJDkLCRvxF\nkk9nWvPorpjjjxaIVN+TkGgDd/60at/tI6HxzZitVyla5rB8hoPm\n-----END RSA PRIVATE KEY-----"
            -- payload = {"aaa":"11","bb":"222"}

            local sign = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1yczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.Zvp8dXefvGXrKgeoaNsA3sbV_3fw1w6Te7a0B_UANzef7gGJwvlnD6c3-f4yAy7GPgNzP_H1-atcF-sgLHAYpUa14XKe22a9S_BJSoQszoZuqGgpnGcjSzDMK9JX3FLUtzOFMQR5C4_3d7_z0NlepNo2xdQ6IQj0SvS1jrNwydpA9L89N07id3EO739uNw339g78N9QHP-j8nWItfbjo31xefCWTHtcloGkfaJOhcr06qmSbrivBU1AuPA8T3ZVumqw6fcRJzrvQJdKEfVyP-IPUtUy8SM1yLqstaKojJtU3A2HKaeb4fycwHXxtl52xhzIshr_I3iUhX_ak-z7m0A"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 35: JWT sign with the public key when using the RS256 algorithm
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
                            "public_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
                        }
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 36: JWT sign and verify RS256
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
--- response_body
passed



=== TEST 37: sanity(algorithm = HS512)
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

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/{"algorithm":"HS512","base64_secret":false,"exp":86400,"key":"123","lifetime_grace_period":0,"secret":"[a-zA-Z0-9+\\\/]+={0,2}"}/



=== TEST 38: add consumer with username and plugins use HS512 algorithm
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
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 39: JWT sign and verify use HS512 algorithm
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
--- response_body
passed



=== TEST 40: sign / verify (algorithm = HS512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local sign = "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1IUzUxMiIsIm5iZiI6MTcyNzI3NDk4M30.emzmjIbFqkRAr55YW5YobdXDxYWiMuUNLPooE5G_bbme1ul19p1dKW7ESrlqvr4BPJRKThm4PnkNC4h9xSJpBQ"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 41: sign / verify (algorithm = HS512,with extra payload)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- payload = {"aaa":"11","bb":"222"}

            local sign = "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhYWEiOiIxMSIsImJiIjoiMjIyIiwia2V5IjoidXNlci1rZXktSFM1MTIiLCJuYmYiOjE3MjcyNzQ5ODN9.s6E3-wNJypgJL71MxoyTTHBDeqdrGQddFjkhLlh3ZN6IZwgpFRlFT1_8suQg9dWUDHGQqgejULyLPhmBMIbw2A"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 42: test for unsupported algorithm
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {key = "123", algorithm = "ES512"}

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/property "algorithm" validation failed/



=== TEST 43: wrong format of secret
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwt-auth")
            local ok, err = plugin.check_schema({
                key = "123",
                secret = "{^c0j4&]2!=J=",
                base64_secret = true,
            }, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
base64_secret required but the secret is not in base64 format



=== TEST 44: when the exp value is not set, make sure the default value(86400) works
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, res = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "exp-not-set",
                            "secret": "my-secret-key"
                        }
                    }
                }]]
            )

            res = require("toolkit.json").decode(res)
            assert(res.value.plugins["jwt-auth"].exp == 86400)

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 45: RS256 without public key
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
                            "algorithm": "RS256",
                            "key": "user-key"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/failed to validate dependent schema for \\"algorithm\\"/



=== TEST 46: RS256 without private key
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
                            "algorithm": "RS256",
                            "key": "user-key",
                            "public_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 200



=== TEST 47: add consumer with username and plugins with public_key
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
                            "key": "user-key-es256",
                            "algorithm": "ES256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEVs/o5+uQbTjL3chynL4wXgUg2R9\nq9UU8I5mEovUf86QZ7kOBIjJwqnzD1omageEHWwHdBO6B+dFabmdT9POxg==\n-----END PUBLIC KEY-----"
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
--- response_body
passed



=== TEST 48: JWT sign and verify use ES256 algorithm(private_key numbits = 512)
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
--- response_body
passed
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 49: sign/verify use ES256 algorithm(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- the jwt signature is encoded with this private_key
            -- private_key = "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2\nOF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r\n1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G\n-----END PRIVATE KEY-----"

            local sign = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleS1lczI1NiIsIm5iZiI6MTcyNzI3NDk4M30.t-CZzJRSxIuVVjU3m8_zDtb7h9x2R2s3BJWmerh0hw-RMIklBqLJ3V9kYAWl7DIyXlp0jQCPDZ_M7mhr1Q3HPw"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- skip_eval
1: $ENV{OPENSSL_FIPS} eq 'yes'



=== TEST 50: add consumer missing public_key (algorithm=RS256)
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
                            "key": "user-key-res256",
                            "algorithm": "RS256"
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin jwt-auth err: failed to validate dependent schema for \"algorithm\": value should match only one schema, but matches none"}



=== TEST 51: add consumer missing public_key (algorithm=RS256)
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
                            "key": "user-key-es256",
                            "algorithm": "ES256"
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin jwt-auth err: failed to validate dependent schema for \"algorithm\": value should match only one schema, but matches none"}
