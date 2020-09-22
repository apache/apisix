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
                            "secret_key": "my-secret-key"
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
                                    "clock_skew": 300
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: value should match only one schema, but matches none"\}/
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: value should match only one schema, but matches none"\}/
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: value should match only one schema, but matches none"\}/
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: value should match only one schema, but matches none"\}/
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
X-HMAC-TIMESTAMP: 112
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
X-HMAC-TIMESTAMP: 112
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"algorithm ljlj not supported"}
--- no_error_log
[error]



=== TEST 10: verify: invalid timestamp
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
X-HMAC-TIMESTAMP: 112
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"Invalid timestamp"}
--- no_error_log
[error]



=== TEST 11: verify: ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
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



=== TEST 12: add consumer with 0 clock skew
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



=== TEST 13: verify: invalid signature
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
X-HMAC-TIMESTAMP: 112
X-HMAC-ACCESS-KEY: my-access-key3
--- error_code: 401
--- response_body
{"message":"Invalid signature"}
--- no_error_log
[error]



=== TEST 14: add consumer with 1 clock skew
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



=== TEST 15: verify: invalid timestamp
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key2"
        local timestamp = ngx_time()
        local access_key = "my-access-key2"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"
        
        ngx.sleep(2)

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
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
qr/\{"message":"Invalid timestamp"\}/
--- no_error_log
[error]



=== TEST 16: verify: put ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "PUT" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
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



=== TEST 17: verify: put ok (pass auth data by header `Authorization`)
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = "ssl_cert", key = "ssl_key", sni = "test.com"}
        local req_body = core.json.encode(data)
        req_body = req_body or ""

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "PUT" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a .. custom_header_b
        core.log.info("signing_string:", signing_string)
        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local auth_string = "hmac-auth-v2#" .. access_key .. "#" .. ngx_encode_base64(signature) .. "#" ..
        "hmac-sha256#" .. timestamp .. "#x-custom-header-a;x-custom-header-b"
        
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



=== TEST 18: hit route without auth info
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"access key or signature missing"}
--- no_error_log
[error]



=== TEST 19: add consumer with signed_headers
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
                                    "clock_skew": 300,
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



=== TEST 20: verify with invalid signed header
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key5"
        local timestamp = ngx_time()
        local access_key = "my-access-key5"
        local custom_header_a = "asld$%dfasf"
        local custom_header_c = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a .. custom_header_c

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
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



=== TEST 21: verify ok with signed headers
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key5"
        local timestamp = ngx_time()
        local access_key = "my-access-key5"
        local custom_header_a = "asld$%dfasf"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. timestamp .. custom_header_a

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
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
