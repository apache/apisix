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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
        if (!$block->response_body) {
            $block->set_value("response_body", "passed\n");
        }
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



=== TEST 2: enable jwt auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key",
                            "key_claim_name": "iss"
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
--- config
    location /t {
        content_by_lua_block {
            local function gen_token(payload)
                local buffer = require "string.buffer"
                local openssl_mac = require "resty.openssl.mac"

                local base64 = require "ngx.base64"
                local base64_encode = base64.encode_base64url

                local json = require("cjson")

                local function sign(data, key)
                    return openssl_mac.new(key, "HMAC", nil, "sha256"):final(data)
                end
                local header = { typ = "JWT", alg = "HS256" }
                local buf = buffer.new()

                buf:put(base64_encode(json.encode(header))):put("."):put(base64_encode(json.encode(payload)))

                local ok, signature = pcall(sign, buf:tostring(), "my-secret-key")
                if not ok then
                    return nil, signature
                end

                buf:put("."):put(base64_encode(signature))

                return buf:get()
            end

            local payload = {
                sub = "1234567890",
                iss = "user-key",
                exp = 9916239022
            }

            local token = gen_token(payload)
            
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local opt = {method = "POST", headers = {["Authorization"] = "Bearer " .. token}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)

            ngx.print(res.body)
        }
    }
--- request
GET /t
--- more_headers
--- response_body
hello world
