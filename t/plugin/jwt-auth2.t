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



=== TEST 2: enable jwt auth plugin using admin api with custom parameter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "header": "jwt-header",
                            "query": "jwt-query",
                            "cookie": "jwt-cookie"
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



=== TEST 3: verify (in header)
--- request
GET /hello
--- more_headers
jwt-header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 4: verify (in cookie)
--- request
GET /hello
--- more_headers
Cookie: jwt-cookie=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 5: verify (in query)
--- request
GET /hello?jwt-query=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 6: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
jwt-header: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 7: verify (in header with bearer)
--- request
GET /hello
--- more_headers
jwt-header: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world



=== TEST 8: use lifetime_grace_period default value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- in order to modify the system_leeway in jwt-validators module
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
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
                ngx.say(body)
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = [[Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A]]
                    }
                })
            ngx.status = res.status
            if res.status >= 300 then
                ngx.status = res.status
                ngx.say(res.body)
                return
            end

            -- add consumer
            local code, body, res_data = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "exp": 1,
                            "algorithm": "HS256",
                            "base64_secret": false,
                            "secret": "test-jwt-secret",
                            "key": "test-jwt-a"
                        }
                    }
                }]]
             )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            -- add route
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "query": "jwt",
                            "header": "Mytoken",
                            "cookie": "jwt"
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
                ngx.say(body)
            end

            -- resgiter jwt sign api
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
                ngx.say(body)
            end

            -- get JWT token
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=test-jwt-a',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            -- verify JWT token
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers={Mytoken=sign}})

            -- the JWT has not expired, so it should be valid
            if res.status >= 300 then
                ngx.status = res.status
                ngx.say(res.body)
                return
            end

            -- after 1.1 seconds, the JWT should be expired, because the exp is only 1 second
            ngx.sleep(1.1)
            res, err = httpc:request_uri(uri, {headers={Mytoken=sign}})
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- error_code: 401
--- response_body eval
qr/failed to verify jwt/
--- error_log eval
qr/ailed to verify jwt: 'exp' claim expired at/



=== TEST 9: lifetime_grace_period is 2 seconds
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- in order to modify the system_leeway in jwt-validators module
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
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
                ngx.say(body)
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = [[Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A]]
                    }
                })
            ngx.status = res.status
            if res.status >= 300 then
                ngx.status = res.status
                ngx.say(res.body)
                return
            end

            -- add consumer
            local code, body, res_data = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "exp": 1,
                            "algorithm": "HS256",
                            "base64_secret": false,
                            "secret": "test-jwt-secret",
                            "key": "test-jwt-a",
                            "lifetime_grace_period": 2
                        }
                    }
                }]]
             )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            -- add route
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "query": "jwt",
                            "header": "Mytoken",
                            "cookie": "jwt"
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
                ngx.say(body)
            end

            -- resgiter jwt sign api
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
                ngx.say(body)
            end

            -- get JWT token
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=test-jwt-a',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            -- verify JWT token
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- after 1.1 seconds, since lifetime_grace_period is 2 seconds,
            -- so the JWT has not expired, it should be valid
            ngx.sleep(1.1)
            local res, err = httpc:request_uri(uri, {headers={Mytoken=sign}})
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- response_body
hello world
