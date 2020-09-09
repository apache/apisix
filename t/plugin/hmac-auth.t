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
BEGIN {
    $ENV{"CUSTOM_HMAC_AUTH"} = "false"
}

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



=== TEST 2: add consumer with plugin hmac-auth - missing secret key
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
                    "username": "jack",
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
--- no_error_log
[error]



=== TEST 4: enable hmac auth plugin using admin api
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



=== TEST 5: verify, missing signature
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"access key or signature missing"}
--- no_error_log
[error]



=== TEST 6: verify: invalid access key
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



=== TEST 7: verify: invalid algorithm
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: ljlj
X-HMAC-TIMESTAMP: 112
X-HMAC-ACCESS-KEY: sdf
--- error_code: 401
--- response_body
{"message":"Invalid access key"}
--- no_error_log
[error]



=== TEST 8: verify: invalid algorithm
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
X-HMAC-TIMESTAMP: 112
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"Invalid signature"}
--- no_error_log
[error]



=== TEST 9: verify: ok
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
        local signing_string = "GET" .. "/hello" ..  "" ..
        "" .. access_key .. timestamp .. secret_key

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
        headers["X-HMAC-ACCESS-KEY"] = access_key

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
--- response_body
passed
--- no_error_log
[error]



=== TEST 10: update consumer with clock skew
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



=== TEST 11: verify: invalid timestamp
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
        local signing_string = "GET" .. "/hello" ..  "" ..
        "" .. access_key .. timestamp .. secret_key

        ngx.sleep(2)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
        headers["X-HMAC-ACCESS-KEY"] = access_key

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



=== TEST 12: verify: put ok
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}
        local req_body = core.json.encode(data)
        local body_hash = ngx.md5(req_body)

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local access_key = "my-access-key"
        local signing_string = "PUT" .. "/hello" ..  "" ..
        body_hash .. access_key .. timestamp .. secret_key

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-HMAC-TIMESTAMP"] = timestamp
        headers["X-HMAC-ACCESS-KEY"] = access_key

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
