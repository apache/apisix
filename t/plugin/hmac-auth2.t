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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: enable the hmac auth plugin
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
--- response_body
passed



=== TEST 2: keep_headers field is empty
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
--- response_body
passed



=== TEST 3: verify pass(keep_headers field is empty), remove http request header
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
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1:1984
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-real-ip: 127.0.0.1



=== TEST 4: keep_headers field is false
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
--- response_body
passed



=== TEST 5: verify pass(keep_headers field is false), remove http request header
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
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1:1984
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-real-ip: 127.0.0.1



=== TEST 6: keep_headers field is true
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
--- response_body
passed



=== TEST 7: verify pass(keep_headers field is true), keep http request header
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
--- response_body
uri: /uri
content-length: 52
content-type: application/x-www-form-urlencoded
host: 127.0.0.1:1984
x-custom-header-a: asld$%dfasf
x-custom-header-b: 23879fmsldfk
x-hmac-access-key: my-access-key4
x-hmac-algorithm: hmac-sha256
x-hmac-signed-headers: x-custom-header-a;x-custom-header-b
x-real-ip: 127.0.0.1



=== TEST 8: get the default schema
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



=== TEST 9: get the schema by schema_type
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



=== TEST 10: get the schema by error schema_type
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



=== TEST 11: enable hmac auth plugin using admin api
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
--- response_body
passed



=== TEST 12: encode_uri_params field is true, the signature of uri enables escaping
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
--- response_body
passed



=== TEST 13: verify: invalid signature (Lowercase letters of escape characters are converted to uppercase.)
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
--- error_code: 401
--- response_body eval
qr/\{"message":"Invalid signature"\}/
--- error_log eval
qr/name=LeBron\%2Cjames\&name2=\%2C\%3E/



=== TEST 14: verify: ok (The letters in the escape character are all uppercase.)
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
--- response_body
passed
--- no_error_log



=== TEST 15: encode_uri_params field is false, uri’s signature is enabled for escaping
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
--- response_body
passed



=== TEST 16: verify: invalid signature (uri’s signature is enabled for escaping)
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
--- error_code: 401
--- response_body eval
qr/\{"message":"Invalid signature"\}/



=== TEST 17: verify: ok
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
--- response_body
passed



=== TEST 18: verify: ok, the request parameter is missing `=<value>`.
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
--- response_body
passed



=== TEST 19: verify: ok, the value of the request parameter is true.
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
--- response_body
passed
