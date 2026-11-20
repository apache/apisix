#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: reject non-canonical compact serializations
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
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "jwt-auth": {}
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- sign a token whose segments contain both '-' and '_'
            local jwt = require("resty.jwt")
            local exp = ngx.time() + 3600
            local token
            repeat
                exp = exp + 1
                token = jwt:sign("my-secret-key", {
                    header = {alg = "HS256", typ = "JWT"},
                    payload = {key = "user-key", exp = exp},
                })
            until token:find("-", 1, true) and token:find("_", 1, true)

            local segs = {}
            for s in token:gmatch("[^%.]+") do
                segs[#segs+1] = s
            end
            local function pad(s)
                return s .. string.rep("=", (-#s) % 4)
            end
            local padded = pad(segs[1]) .. "." .. pad(segs[2]) .. "." .. pad(segs[3])
            local std_alphabet = token:gsub("-", "+"):gsub("_", "/")

            local parser = require("apisix.plugins.jwt-auth.parser")
            local ok, err = parser.new(token)
            ngx.say("parser canonical: ", ok and "accepted" or ("rejected: " .. tostring(err)))
            local ok, err = parser.new(padded)
            ngx.say("parser padded: ", ok and "accepted" or ("rejected: " .. tostring(err)))
            local ok, err = parser.new(std_alphabet)
            ngx.say("parser std alphabet: ", ok and "accepted" or ("rejected: " .. tostring(err)))
            local ok, err = parser.new("a.b.c.d")
            ngx.say("parser four parts: ", ok and "accepted" or ("rejected: " .. tostring(err)))

            local http = require "resty.http"
            local httpc = http.new()
            local function status(tok)
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                    {method = "GET", headers = {Authorization = "Bearer " .. tok}})
                if not res then
                    return "err: " .. err
                end
                return res.status
            end
            ngx.say("request canonical: ", status(token))
            ngx.say("request padded: ", status(padded))
            ngx.say("request std alphabet: ", status(std_alphabet))
        }
    }
--- response_body
parser canonical: accepted
parser padded: rejected: invalid jwt string: non-canonical base64url in payload
parser std alphabet: rejected: invalid jwt string: non-canonical base64url in signature
parser four parts: rejected: invalid jwt string
request canonical: 200
request padded: 401
request std alphabet: 401
