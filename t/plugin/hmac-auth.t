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



=== TEST 7: verify, missing signature
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: access key or signature missing



=== TEST 8: verify, missing algorithm
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: algorithm missing



=== TEST 9: verify: invalid access key
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: sdf
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid access key



=== TEST 10: verify: invalid algorithm
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: ljlj
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: algorithm ljlj not supported



=== TEST 11: verify: Clock skew exceeded
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Clock skew exceeded



=== TEST 12: verify: missing Date
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid GMT format time



=== TEST 13: verify: Invalid GMT format time
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: adfsdf
X-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid GMT format time



=== TEST 14: verify: ok
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



=== TEST 15: add consumer with 0 clock skew
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



=== TEST 16: verify: invalid signature
--- request
GET /hello
--- more_headers
X-HMAC-SIGNATURE: asdf
X-HMAC-ALGORITHM: hmac-sha256
Date: Thu, 24 Sep 2020 06:39:52 GMT
X-HMAC-ACCESS-KEY: my-access-key3
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signature



=== TEST 17: add consumer with 1 clock skew
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



=== TEST 18: verify: Invalid GMT format time
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
qr/{"message":"client request can't be validated"}/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Clock skew exceeded



=== TEST 19: verify: put ok
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



=== TEST 20: verify: put ok (pass auth data by header `Authorization`)
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



=== TEST 21: hit route without auth info
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: access key or signature missing



=== TEST 22: add consumer with signed_headers
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



=== TEST 23: verify with invalid signed header
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
qr/{"message":"client request can't be validated"}/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signed header x-custom-header-c



=== TEST 24: verify ok with signed headers
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



=== TEST 25: add consumer with plugin hmac-auth - empty configuration
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
