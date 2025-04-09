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
                        "hmac-auth": {
                            "validate_request_body": true
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



=== TEST 3: missing body digest when validate_request_body is enabled
--- config
    location /t {
        content_by_lua_block {
            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.openssl.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                 key_id,
                "POST /hello",
                "date: " .. gmt,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac.new(secret_key, "sm3"):final(signing_string)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sm3\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
            local hmac = require("resty.openssl.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac.new(secret_key, "sm3"):final(signing_string)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Authorization"] ="Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sm3\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["Digest"] = "hello"
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
            local hmac = require("resty.openssl.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac.new(secret_key, "sm3"):final(signing_string)
            local ngx_encode_base64 = ngx.encode_base64

            local digest = hmac.new(secret_key, "sm3"):final(body)
            local body_digest = ngx_encode_base64(digest)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Digest"] = "SHA-256=" .. body_digest
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sm3\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
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
