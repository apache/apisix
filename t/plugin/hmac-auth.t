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
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
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
                            "key_id": "user-key"
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



=== TEST 3: add consumer with plugin hmac-auth - missing key_id
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"key_id\\" is required"\}/



=== TEST 4: add consumer with plugin hmac-auth - key id exceeds the length limit
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
                            "key_id": "akeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakeyakey",
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"key_id\\" validation failed: string too long, expected at most 256, got 320"\}/



=== TEST 5: add consumer with plugin hmac-auth - secret key exceeds the length limit
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
                            "key_id": "akey",
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



=== TEST 7: verify,missing Authorization header
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"client request can't be validated: missing Authorization header"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: missing Authorization header



=== TEST 8: verify, missing algorithm
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",headers="@request-target date" ,signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated[^,]+/
--- grep_error_log_out
client request can't be validated: algorithm missing



=== TEST 9: verify: invalid key_id
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="sdf",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid key_id



=== TEST 10: verify: invalid algorithm
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",algorithm="ljlj",headers="@request-target date",signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid algorithm



=== TEST 11: verify: Clock skew exceeded
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
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
Authorization: Signature keyId="my-access-key",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: Date header missing/
--- grep_error_log_out
client request can't be validated: Date header missing



=== TEST 13: verify: Invalid GMT format time
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
Date: adfsdf
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
             key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature algorithm=\"hmac-sha256\"" .. ",keyId=\"" .. key_id .. "\",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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



=== TEST 15: add route with 0 clock skew
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "clock_skew":  0
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
            if code == 400 then
                ngx.say(body)
            end
        }
    }
--- request
GET /t
-- error_code: 400
--- response_body eval
qr/.*failed to check the configuration of plugin hmac-auth err.*/



=== TEST 16: add route with valid clock skew
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key3",
                            "secret_key": "my-secret-key3",
                            "clock_skew":  1000000000000
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
            if code == 200 then
                ngx.say(body)
            end
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 17: verify: invalid signature
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signature



=== TEST 18: verify: invalid signature
--- request
GET /hello
--- more_headers
Authorization: Signature keyId="my-access-key",algorithm="hmac-sha256",headers="@request-target date",signature="asdf"
Date: Thu, 24 Sep 2020 06:39:52 GMT
--- error_code: 401
--- response_body
{"message":"client request can't be validated"}
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signature



=== TEST 19: add route with 1 clock skew
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "clock_skew":  1
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
            if code == 200 then
                ngx.say(body)
            end
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 20: verify: Invalid GMT format time
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        ngx.sleep(2)

        local signing_string = "GET" .. "/hello" ..  "" ..
            key_id .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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



=== TEST 21: update route with default clock skew
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
            if code == 200 then
                ngx.say(body)
            end
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 22: verify: put ok
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            key_id,
            "PUT /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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



=== TEST 23: update route with signed_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "signed_headers": ["date","x-custom-header-a", "x-custom-header-b"]
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



=== TEST 24: verify with invalid signed header
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_c = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            key_id .. gmt .. custom_header_a .. custom_header_c

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-c\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
client request can't be validated: expected header "x-custom-header-b" missing in signing



=== TEST 25: verify ok with signed headers
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "asld$%dfasf"

        local signing_string = {
            key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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



=== TEST 26: add consumer with plugin hmac-auth - empty configuration
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
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin hmac-auth err: property \\"(key_id|secret_key)\\" is required"\}/



=== TEST 27: add route with no allowed algorithms
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "allowed_algorithms": []
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
--- response_body eval
qr/validation failed: expect array to have at least 1 items/



=== TEST 28: update route with signed_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "hide_credentials": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "httpbin.org:80": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/headers"
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



=== TEST 29: verify Authorization header missing
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
        local key_id = "my-access-key"

        local signing_string = {
            key_id,
            "GET /headers",
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        local code, _, body = t.test('/headers',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        if string.find(body,"Authorization") then
            ngx.say("failed")
        else
            ngx.say("passed")
        end
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 30 : update route with signed_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "signed_headers": ["date","x-custom-header-a", "x-custom-header-b"]
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



=== TEST 31: verify error with the client only sends one in the request, but there are two in the signature
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "asld$%dfasf"

        local signing_string = {
            key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
--- error_code: 401
--- response_body eval
qr/client request can't be validated/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signature



=== TEST 32: verify error with the client sends two in the request, but there is only one in the signature
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "asld$%dfasf"

        local signing_string = {
            key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
--- error_code: 401
--- response_body eval
qr/client request can't be validated/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid signature



=== TEST 33 : update route with allowed_algorithms
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "allowed_algorithms": ["hmac-sha256"]
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



=== TEST 34: verify with hmac-sha1 algorithm, not part of allowed_algorithms
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
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "asld$%dfasf"

        local signing_string = {
            key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA1):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha1\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
--- error_code: 401
--- response_body eval
qr/client request can't be validated/
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid algorithm
