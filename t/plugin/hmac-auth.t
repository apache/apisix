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
                        "hmac-auth": {
                            "access_key": "my-access-key",
                            "secret_key": "my-secret-key",
                            "clock_skew": 10
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key",
                                    "secret_key": "my-secret-key",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 10
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



=== TEST 2: add consumer with plugin hmac-auth - missing secret key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "user-key"
                        }
                    }
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"secret_key\\" is required"\}/
--- no_error_log
[error]



=== TEST 3: add consumer with plugin hmac-auth - missing access key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "bar",
                    "plugins": {
                        "hmac-auth": {
                            "secret_key": "skey"
                        }
                    }
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"access_key\\" is required"\}/
--- no_error_log
[error]



=== TEST 4: add consumer with plugin hmac-auth - access key exceeds the length limit
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "li",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "akeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakey",
                            "secret_key": "skey"
                        }
                    }
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"access_key\\" validation failed: string too long, expected at most 256, got 320"\}/
--- no_error_log
[error]



=== TEST 5: add consumer with plugin hmac-auth - access key exceeds the length limit
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "zhang",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "akey",
                            "secret_key": "skeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskeyskey"
                        }
                    }
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"secret_key\\" validation failed: string too long, expected at most 256, got 384"\}/
--- no_error_log
[error]



=== TEST 6: enable hmac auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
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



=== TEST 7: verify, missing signature
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"access key or signature missing"}
--- no_error_log
[error]



=== TEST 8: verify: invalid access key
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: sdf
--- error_code: 401
--- response_body
{"message":"Invalid access key"}
--- no_error_log
[error]



=== TEST 9: verify: invalid algorithm
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: ljlj
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"algorithm ljlj not supported"}
--- no_error_log
[error]



=== TEST 10: verify: Clock skew exceeded
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"Clock skew exceeded"}
--- no_error_log
[error]



=== TEST 11: verify: missing Date
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"Invalid GMT format time"}
--- no_error_log
[error]



=== TEST 12: verify: Invalid GMT format time
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: adfsdf
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"Invalid GMT format time"}
--- no_error_log
[error]



=== TEST 13: verify: ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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



=== TEST 14: add consumer with 0 clock skew
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "robin",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key3",
                            "secret_key": "my-secret-key3",
                            "clock_skew": 0
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "robin",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key3",
                                    "secret_key": "my-secret-key3",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 0
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



=== TEST 15: verify: invalid signature
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key3
--- error_code: 401
--- response_body
{"message":"Invalid signature"}
--- no_error_log
[error]



=== TEST 16: add consumer with 1 clock skew
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "pony",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key2",
                            "secret_key": "my-secret-key2",
                            "clock_skew": 1
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "pony",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key2",
                                    "secret_key": "my-secret-key2",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 1
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



=== TEST 17: verify: Invalid GMT format time
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key2"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key2"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        ngx.sleep(2)

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            core.json.encode(data),
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"Clock skew exceeded"\}/
--- no_error_log
[error]



=== TEST 18: verify: put ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "PUT",
            "/hello",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_PUT,
            req_body,
            nil,
            headers
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



=== TEST 19: verify: put ok (pass auth data by header `Authorization`)
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time   = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "PUT",
            "/hello",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        core.log.info("signing_string:", signing_string)
        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local auth_string = "hmac-auth-v1#" .. access_key .. "#" .. ngx_encode_base64(signature) .. "#" ..
        "hmac-sha256#" .. gmt .. "#x-custom-header-a;x-custom-header-b"

        local headers = {}
        headers["Authorization"] = auth_string
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_PUT,
            req_body,
            nil,
            headers
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



=== TEST 20: hit route without auth info
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"access key or signature missing"}
--- no_error_log
[error]



=== TEST 21: add consumer with signed_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "cook",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key5",
                            "secret_key": "my-secret-key5",
                            "signed_headers": ["x-custom-header-a", "x-custom-header-b"]
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "cook",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key5",
                                    "secret_key": "my-secret-key5",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 0,
                                    "signed_headers": ["x-custom-header-a", "x-custom-header-b"]
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



=== TEST 22: verify with invalid signed header
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key5"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key5"
        local custom_header_a = "asld$%dfasf"
        local custom_header_c = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_c

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-c"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-c"] = custom_header_c

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"Invalid signed header x-custom-header-c"\}/
--- no_error_log
[error]



=== TEST 23: verify ok with signed headers
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key5"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key5"
        local custom_header_a = "asld$%dfasf"

        local signing_string = {
            "GET",
            "/hello",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a"
        headers["x-custom-header-a"] = custom_header_a

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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



=== TEST 24: add consumer with plugin hmac-auth - empty configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "hmac-auth": {
                        }
                    }
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"(access|secret)_key\\" is required"\}/
--- no_error_log
[error]



=== TEST 25: enable the hmac auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/uri"
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



=== TEST 26: keep_headers field is empty
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "james",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key4",
                            "secret_key": "my-secret-key4"                           
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



=== TEST 27: verify pass(keep_headers field is empty), remove http request header
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_re = require("ngx.re")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key4"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key4"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "PUT",
            "/uri",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, _, body = t.test('/uri',
            ngx.HTTP_PUT,
            req_body,
            nil,
            headers
        )
        
        if code >= 300 then
            ngx.status = code
        end

        local headers_arr = ngx_re.split(body, "\n")
        for i, v in ipairs(headers_arr) do
            if i ~= 4 and i ~= 6 then      -- skip date and user-agent field
                ngx.say(v)
            end
        end
    }
}
--- request
GET /t
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 28: keep_headers field is false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "james",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key4",
                            "secret_key": "my-secret-key4",
                            "keep_headers": false
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



=== TEST 29: verify pass(keep_headers field is false), remove http request header
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_re = require("ngx.re")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key4"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key4"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "PUT",
            "/uri",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, _, body = t.test('/uri',
            ngx.HTTP_PUT,
            req_body,
            nil,
            headers
        )

        if code >= 300 then
            ngx.status = code
        end

        local headers_arr = ngx_re.split(body, "\n")
        for i, v in ipairs(headers_arr) do
            if i ~= 4 and i ~= 6 then      -- skip date and user-agent field
                ngx.say(v)
            end
        end
    }
}
--- request
GET /t
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 30: keep_headers field is true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "james",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key4",
                            "secret_key": "my-secret-key4",
                            "keep_headers": true
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



=== TEST 31: verify pass(keep_headers field is true), keep http request header
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_re = require("ngx.re")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key4"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key4"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "PUT",
            "/uri",
            "",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, _, body = t.test('/uri',
            ngx.HTTP_PUT,
            req_body,
            nil,
            headers
        )

        if code >= 300 then
            ngx.status = code
        end

        local headers_arr = ngx_re.split(body, "\n")
        for i, v in ipairs(headers_arr) do
            if i ~= 4 and i ~= 6 and i ~= 11 then      -- skip date, user-agent and x-hmac-signature field
                ngx.say(v)
            end
        end
    }
}
--- request
GET /t
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-hmac-algorithm: hmac-sha256
x-hmac-signed-headers: x-custom-header-a;x-custom-header-b
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 32: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"title":"work with route or service object","additionalProperties":false,"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 33: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","additionalProperties":false,"required":["access_key","secret_key"],"properties":{"clock_skew":{"default":0,"type":"integer"},"encode_uri_params":{"title":"Whether to escape the uri parameter","default":true,"type":"boolean"},"keep_headers":{"title":"whether to keep the http request header","default":false,"type":"boolean"},"secret_key":{"minLength":1,"maxLength":256,"type":"string"},"algorithm":{"type":"string","default":"hmac-sha256","enum":["hmac-sha1","hmac-sha256","hmac-sha512"]},"signed_headers":{"items":{"minLength":1,"maxLength":50,"type":"string"},"type":"array"},"access_key":{"minLength":1,"maxLength":256,"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 34: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"title":"work with route or service object","additionalProperties":false,"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 35: enable hmac auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
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



=== TEST 36: encode_uri_params field is true, the signature of uri enables escaping
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "james",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key6",
                            "secret_key": "my-secret-key6"
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



=== TEST 37: verify: invalid signature (Lowercase letters of escape characters are converted to uppercase.)
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "name=LeBron%2Cjames&name2=%2c%3e",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=LeBron%2Cjames&name2=%2c%3e',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"Invalid signature"\}/
--- error_log eval
qr/name=LeBron\%2Cjames\&name2=\%2C\%3E/



=== TEST 38: verify: ok (The letters in the escape character are all uppercase.)
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "name=LeBron%2Cjames&name2=%2C%3E",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=LeBron%2Cjames&name2=%2C%3E',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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



=== TEST 39: encode_uri_params field is false, uri’s signature is enabled for escaping
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "james",
                    "plugins": {
                        "hmac-auth": {
                            "access_key": "my-access-key6",
                            "secret_key": "my-secret-key6",
                            "encode_uri_params": false
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



=== TEST 40: verify: invalid signature (uri’s signature is enabled for escaping)
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "name=LeBron%2Cjames&name2=%2c%3e",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=LeBron%2Cjames&name2=%2c%3e',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"Invalid signature"\}/
--- no_error_log
[error]



=== TEST 41: verify: ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "name=LeBron,james&name2=,>",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=LeBron%2Cjames&name2=%2c%3e',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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



=== TEST 42: verify: ok, the request parameter is missing `=<value>`.
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "age=&name=jack",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=jack&age',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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



=== TEST 43: verify: ok, the value of the request parameter is true.
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key6"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local access_key = "my-access-key6"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            "GET",
            "/hello",
            "age=true&name=jack",
            access_key,
            gmt,
            "x-custom-header-a:" .. custom_header_a,
            "x-custom-header-b:" .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello?name=jack&age=true',
            ngx.HTTP_GET,
            "",
            nil,
            headers
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
