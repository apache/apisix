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
log_level("debug");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: add consumer with username and plugins
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
                            "secret": "my-secret-key",
                            "algorithm": "HS384"
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



=== TEST 2: enable jwt auth plugin using admin api
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



=== TEST 3: create public API route (jwt-auth sign)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/jwt/sign"
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



=== TEST 4: sign / verify in argument
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzM4NCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MjA4NTA4Nzc5Mn0.6BNfYOnGvB27uY5LIwZFgIV_g42wiqLSlITtgAXinuZA9DNcquCTiudmbaXCHj20',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- error_log
"alg":"HS384"



=== TEST 5: verify: invalid JWT token
--- request
GET /hello?jwt=invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- error_code: 401
--- response_body
{"message":"JWT token invalid"}
--- error_log
JWT token invalid: invalid header: invalid-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9



=== TEST 6: verify token with algorithm HS256
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
--- error_log
"alg":"HS256"



=== TEST 7: missing public key and private key
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
                            "secret": "my-secret-key",
                            "algorithm": "PS256"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin jwt-auth err: failed to validate dependent schema for \"algorithm\": value should match only one schema, but matches none"}



=== TEST 8: missing public key and private key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson").encode
            local cons_tab = {
                username = "jack",
                plugins = {
                    ["jwt-auth"] = {
                        key = "user-key2",
                        secret = "my-secret-key",
                        algorithm = "PS256",
                        public_key = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiSpoCgu3GzeExroi2YQ+\nxcQlXqEO8D5/5DgrlGsEb3Y9kEX+lj3ayW/G93nAob1xrtpjzBLf4chDivcmMj1q\nOwggoAOOmC9D/EYzDNKAos/gNcgsxra1X7xdMje+jUYR8nQGLemkidD71XbOrrcy\nLTE886t/lcrauC3dxNl55DkZc22YZWSanmizGfedMIEVtZb08uXbTi+8KyP3d+QL\nKYQ2eSa8AQredrKmM0eREQHr6R+zz6xqgycJ/Pxp+C0UYFbV+LVnHom5u6ck2SNG\nuGI1sBQ3V763BArbGpWlpcetQT5JB8QDhywf1ihNdaJgWhswQJVSMpJ8ZmA8R1Av\nDQIDAQAB\n-----END PUBLIC KEY-----"
                    }
                }
            }
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                json(cons_tab)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: sign / verify in argument
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?jwt=' .. "eyJ0eXAiOiJKV1QiLCJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBaVNwb0NndTNHemVFeHJvaTJZUStcbnhjUWxYcUVPOEQ1LzVEZ3JsR3NFYjNZOWtFWCtsajNheVcvRzkzbkFvYjF4cnRwanpCTGY0Y2hEaXZjbU1qMXFcbk93Z2dvQU9PbUM5RC9FWXpETktBb3MvZ05jZ3N4cmExWDd4ZE1qZStqVVlSOG5RR0xlbWtpZEQ3MVhiT3JyY3lcbkxURTg4NnQvbGNyYXVDM2R4Tmw1NURrWmMyMllaV1Nhbm1pekdmZWRNSUVWdFpiMDh1WGJUaSs4S3lQM2QrUUxcbktZUTJlU2E4QVFyZWRyS21NMGVSRVFIcjZSK3p6NnhxZ3ljSi9QeHArQzBVWUZiVitMVm5Ib201dTZjazJTTkdcbnVHSTFzQlEzVjc2M0JBcmJHcFdscGNldFFUNUpCOFFEaHl3ZjFpaE5kYUpnV2hzd1FKVlNNcEo4Wm1BOFIxQXZcbkRRSURBUUFCXG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwiYWxnIjoiUFMyNTYifQ.eyJrZXkiOiJ1c2VyLWtleTIiLCJleHAiOjIwODUwNjkxMzl9.FmtBZ-LBqyIDQV3lTiN0XaWOrl19D3s6oF3VmbZZ1xoW7gdHVtkMdOs4FrwflxUiZOyAGq7FDBVaHgbzil0LkyXwFqY8EABARUu4S9S3H0xpM6oFXvXsqoA9ygyq5Nty0L8KBI4LMm-rIL0g34pecjZG5cJEbjFhuN4bHM1ZUvJZf-VX6JMmwdueknTY0rIOM7CzComazue3u9JXrDxF1j1xkPInraUmtkUhNM90JuidAgMFVHQb8XN6U-E2Xbn6cD_kXc93Ul4WJK8H2KQNk_gwLmUXBs45wVMzZuEtJ1_nlsPHJztupSE2tSJvwX_YF1EL-v2_OYhgLBSgFsncpw",
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- error_log
"alg":"PS256"



=== TEST 10: verify token with algorithm PS356
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJQUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Ind3dy5iZWpzb24uY29tIiwic3ViIjoiZGVtbyIsImtleSI6InVzZXIta2V5MiIsImV4cCI6MjA4OTcyNDA1N30.cKaijeZ4ydKVKCC37UZObPFj_kVsdiScEuGwK_G9JBjg0dcRnL8Xvr6Ofp8kDJz16FO2vy8FHgA_9HVjVpzehNe-AbtYJ88Qopy2pAQHsottGuQe3jgAt-yBI5chf26GzpqTtyymteg-lt-cW6EoP4gVHfXEbzQaOZt0wmdNBX17jISKW70okdxrp7cJKbv4hXQXjhYwKY8h0jYnGb-RhuHXRwWFhp6TZVV57Lfpi1yUDm6GqXM42W7owOOwjUqS8-7KYv1iugQzTo7qcVjPic7X5Wug7N-4t8BRM9jZkUiNrAY2BoxxBMUUru4fd201KY23p4bZDwQFpg6MVck7XA
--- response_body
hello world



=== TEST 11: add consumer with username and plugins
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
                            "secret": "my-secret-key",
                            "algorithm": "HS384"
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



=== TEST 12: only verify nbf claim
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "claims_to_verify": ["nbf"]
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
--- response_body
passed



=== TEST 13: verify success with expired token
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMX0.pPNVvh-TQsdDzorRwa-uuiLYiEBODscp9wv0cwD6c68
--- response_body
hello world



=== TEST 14: verify failed before nbf claim
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMSwibmJmIjoyMjI5NjcxODc0fQ.RJynr34TyCesYHwvDwOwETi1vOfZXKqc_wvQJ3pijBfrx1x5IF3O1CCUCvd5lMYf
--- error_code: 401
--- response_body eval
qr/failed to verify jwt/
--- error_log
'nbf' claim not valid until Mon, 27 Aug 2040 09:17:54 GMT



=== TEST 15: verify success after nbf claim
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2Mzg3MDUwMSwibmJmIjoxNzI5Njc1MDQyfQ.IycpH4Lc48BHSxUBXBNDXGawvNgi_6a-qsa-xnhYFLooeWc8DyX8zLadvyEFpMPq
--- response_body
hello world



=== TEST 16: EdDSA algorithm
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
                            "secret": "my-secret-key",
                            "algorithm": "EdDSA",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA9PdGVALrrBX4oX5t9DKb5JHYx7XRb0RXU42r0FVO2sA=\n-----END PUBLIC KEY-----",
                            "private_key": "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIKmBJXpq9Fp0K97TpJ2X9V6jszx23j7NtKKa6gZRaAjI\n-----END PRIVATE KEY-----"
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



=== TEST 17: sign / verify in argument
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?jwt=' .. "eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Db3dCUVlESzJWd0F5RUE5UGRHVkFMcnJCWDRvWDV0OURLYjVKSFl4N1hSYjBSWFU0MnIwRlZPMnNBPVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sInR5cCI6IkpXVCIsImFsZyI6IkVkRFNBIn0.eyJleHAiOjIwODUwNzA2MDQsImtleSI6InVzZXIta2V5In0.FmPpxVDubPukcnW58DICZOYMqvkikn4TuUzIQX68-s9KOBUhOgH1_TZM3gUk5Wv0L86c4joVzU7hqstsJSs0Cw",
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world
--- error_log
"alg":"EdDSA"
