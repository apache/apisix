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
log_level('warn');
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        if (!$block->stream_request) {
            $block->set_value("request", "GET /t");
        }
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: enable feishu-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins":{
                        "feishu-auth":{
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/feishu/token",
                            "userinfo_url": "http://127.0.0.1:1980/feishu/userinfo",
                            "cookie_expires_in": 2,
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code <= 201 then
                ngx.status = 200
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: missing code
--- request
GET /hello
--- error_code: 302
--- response_headers
Location: /echo



=== TEST 3: invalid code
--- request
GET /hello?code=invalid
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 4: valid code
--- request
GET /hello?code=passed
--- error_code: 200
--- response_body
hello world



=== TEST 5: X-Feishu-Code with invalid code
--- request
GET /hello
--- more_headers
X-Feishu-Code: invalid
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 6: X-Feishu-Code header
--- request
GET /hello
--- more_headers
X-Feishu-Code: passed
--- error_code: 200
--- response_body
hello world



=== TEST 7: check cookie
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                query = {
                    code = "passed",
                },
                method = "GET",
            })
            assert(res, "request failed: " .. (err or "unknown error"))
            assert(res.status == 200, "unexpected res status: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- request with cookie
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res2, "request failed: " .. (err or "unknown error"))
            assert(res2.status == 200, "unexpected res2 status: " .. res2.status)

            --- request without cookie
            local res3, err = httpc:request_uri(uri, {
                method = "GET",
            })
            assert(res3, "request failed: " .. (err or "unknown error"))
            assert(res3.status == 302, "unexpected res3 status: " .. res3.status)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 8: cookie expire
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                query = {
                    code = "passed",
                },
                method = "GET",
            })
            assert(res, "request failed: " .. (err or "unknown error"))
            assert(res.status == 200, "unexpected res status: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- request with cookie
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res2, "request failed: " .. (err or "unknown error"))
            assert(res2.status == 200, "unexpected res2 status: " .. res2.status)

            ngx.sleep(3)

            --- request without cookie
            local res3, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res3, "request failed: " .. (err or "unknown error"))
            assert(res3.status == 302, "unexpected res3 status: " .. res3.status)

            ngx.say("passed")
        }
    }
--- timeout: 5
--- request
GET /t
--- response_body
passed



=== TEST 9: specify header and query and redirect_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins":{
                        "feishu-auth":{
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/feishu/token",
                            "userinfo_url": "http://127.0.0.1:1980/feishu/userinfo",
                            "code_query": "custom_code",
                            "code_header": "Custom-feishu-Code",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code <= 201 then
                ngx.status = 200
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: specify query
--- pipelined_requests eval
["GET /hello?code=passed", "GET /hello?custom_code=passed"]
--- error_code eval
[302, 200]



=== TEST 11: specify header
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
[
"X-Feishu-Code: passed",
"Custom-Feishu-Code: passed"
]
--- error_code eval
[302, 200]
