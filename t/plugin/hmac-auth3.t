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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: add consumer with validate_request_body
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
                            "access_key": "my-access-key",
                            "secret_key": "my-secret-key",
                            "validate_request_body": true
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



=== TEST 2: enable hmac auth plugin using admin api
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



=== TEST 3: missing body digest when validate_request_body is enabled
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
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
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid digest
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 4: verify body digest: not ok
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
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
            headers["X-HMAC-DIGEST"] = "hello"
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid digest
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 5: verify body digest: ok
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
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
            local body_digest = hmac:new(secret_key, hmac.ALGOS.SHA256):final(body)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
            headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
            headers["Date"] = gmt
            headers["X-HMAC-DIGEST"] = ngx_encode_base64(body_digest)
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: add consumer with max_req_body
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
                            "access_key": "my-access-key",
                            "secret_key": "my-secret-key",
                            "validate_request_body": true,
                            "max_req_body": 1024
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



=== TEST 7: Exceed body limit size
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
            local body = ("-1Aa#"):rep(205)

            local signing_string = {
                "POST",
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
            local body_digest = hmac:new(secret_key, hmac.ALGOS.SHA256):final(body)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
            headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
            headers["Date"] = gmt
            headers["X-HMAC-DIGEST"] = ngx_encode_base64(body_digest)
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Exceed body limit size
--- response_body eval
qr/\{"message":"client request can't be validated"}/



=== TEST 8: Test custom request body digest header name with mismatched header.
--- yaml_config
plugin_attr:
    hmac-auth:
        body_digest_key: "X-Digest-Custom"
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
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
            local body_digest = hmac:new(secret_key, hmac.ALGOS.SHA256):final(body)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
            headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
            headers["Date"] = gmt
            headers["X-HMAC-DIGEST"] = ngx_encode_base64(body_digest)
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid digest
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 9: Test custom request body digest header name.
--- yaml_config
plugin_attr:
    hmac-auth:
        body_digest_key: "X-Digest-Custom"
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
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
            local body_digest = hmac:new(secret_key, hmac.ALGOS.SHA256):final(body)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
            headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
            headers["Date"] = gmt
            headers["X-Digest-Custom"] = ngx_encode_base64(body_digest)
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: Test sort table param.
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
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                "POST",
                "/hello",
                "a=&a=1&a=2&a1a=123&c=&name=123",
                access_key,
                gmt,
                "x-custom-header-a:" .. custom_header_a,
                "x-custom-header-b:" .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
            local body_digest = hmac:new(secret_key, hmac.ALGOS.SHA256):final(body)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
            headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
            headers["Date"] = gmt
            headers["X-HMAC-DIGEST"] = ngx_encode_base64(body_digest)
            headers["X-HMAC-ACCESS-KEY"] = access_key
            headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello?c=&a1a=123&name=123&a&a=2&a=1',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: update consumer
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
--- response_body
passed



=== TEST 12: verify that uri args are greater than 100 is ok
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

        local uri_args = {}
        for i = 1, 101 do
            uri_args["arg_" .. tostring(i)] = "val_" .. tostring(i)
        end
        local keys = {}
        local query_tab = {}

        for k, v in pairs(uri_args) do
            core.table.insert(keys, k)
        end
        core.table.sort(keys)

        local args_str = ""
        for _, key in pairs(keys) do
            args_str = args_str .. key .. "=" .. uri_args[key] .. "&"
        end
        -- remove the last '&'
        args_str = args_str:sub(1, -2)

        local signing_string = {
            "GET",
            "/hello",
            args_str,
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

        local code, body = t.test('/hello' .. '?' .. args_str,
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



=== TEST 13: delete exist consumers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- delete exist consumers
            local code, body = t('/apisix/admin/consumers/robin', ngx.HTTP_DELETE)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: data encryption for secret_key
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
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
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers/jack',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["hmac-auth"].secret_key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/jack'))
            ngx.say(res.body.node.value.plugins["hmac-auth"].secret_key)
        }
    }
--- response_body
my-secret-key
IRWpPjbDq5BCgHyIllnOMA==
