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

    my $extra_yaml_config = <<_EOC_;
plugin_attr:
  hmac-auth:
    signature_key: X-APISIX-HMAC-SIGNATURE
    algorithm_key: X-APISIX-HMAC-ALGORITHM
    date_key: X-APISIX-DATE
    access_key: X-APISIX-HMAC-ACCESS-KEY
    signed_headers_key: X-APISIX-HMAC-SIGNED-HEADERS
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);
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
--- error_code: 400



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
--- error_code: 400



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
--- response_body
passed



=== TEST 5: verify, missing signature
--- request
GET /hello
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: access key or signature missing
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 6: verify: invalid access key
--- request
GET /hello
--- more_headers
X-APISIX-HMAC-SIGNATURE: asdf
X-APISIX-HMAC-ALGORITHM: hmac-sha256
X-APISIX-Date: Thu, 24 Sep 2020 06:39:52 GMT
X-APISIX-HMAC-ACCESS-KEY: sdf
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid access key
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 7: verify: invalid algorithm
--- request
GET /hello
--- more_headers
X-APISIX-HMAC-SIGNATURE: asdf
X-APISIX-HMAC-ALGORITHM: ljlj
X-APISIX-Date: Thu, 24 Sep 2020 06:39:52 GMT
X-APISIX-HMAC-ACCESS-KEY: sdf
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid access key
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 8: verify: Invalid GMT format time
--- request
GET /hello
--- more_headers
X-APISIX-HMAC-SIGNATURE: asdf
X-APISIX-HMAC-ALGORITHM: hmac-sha256
X-APISIX-Date: adfa
X-APISIX-HMAC-ACCESS-KEY: my-access-key
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid GMT format time
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 9: verify: ok
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
        local time = ngx_time()
        local gmt = ngx_http_time(time)
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

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-APISIX-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-APISIX-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-APISIX-DATE"] = gmt
        headers["X-APISIX-HMAC-ACCESS-KEY"] = access_key
        headers["X-APISIX-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
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
--- response_body
passed



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



=== TEST 11: verify: Clock skew exceeded
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
        local time = ngx_time()
        local gmt = ngx_http_time(time)
        local access_key = "my-access-key2"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"
        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        ngx.sleep(2)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-APISIX-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-APISIX-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["X-APISIX-DATE"] = gmt
        headers["X-APISIX-HMAC-ACCESS-KEY"] = access_key

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
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Clock skew exceeded
--- response_body eval
qr/\{"message":"client request can't be validated"\}/
