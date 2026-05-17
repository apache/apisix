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
log_level('debug');
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10421;

        location /v1.0/oauth2/accessToken {
            content_by_lua_block {
                local json = require("toolkit.json")
                ngx.req.read_body()
                ngx.status = 200
                ngx.say(json.encode({
                    accessToken = "test_access_token_12345",
                    expireIn = 7200
                }))
            }
        }

        location /topapi/v2/user/getuserinfo {
            content_by_lua_block {
                local json = require("toolkit.json")
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                local data = json.decode(body)
                if data.code ~= "valid_code" then
                    ngx.status = 200
                    ngx.say(json.encode({
                        errcode = 403,
                        errmsg = "Unauthorized"
                    }))
                    return
                end
                ngx.status = 200
                ngx.say(json.encode({
                    errcode = 0,
                    errmsg = "ok",
                    result = {
                        userid = "user_001",
                        name = "Test User",
                        unionid = "union_abc123"
                    }
                }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema check - all required fields present
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.dingtalk-auth")
            local ok, err = plugin.check_schema({
                app_key = "appkey123",
                app_secret = "appsecret456",
                secret = "session-secret-key",
                redirect_uri = "/login",
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: schema check - missing required field app_key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.dingtalk-auth")
            local ok, err = plugin.check_schema({
                app_secret = "appsecret456",
                secret = "session-secret-key",
                redirect_uri = "/login",
            })
            ngx.say(ok)
        }
    }
--- response_body
false



=== TEST 3: schema check - secret too short
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.dingtalk-auth")
            local ok, err = plugin.check_schema({
                app_key = "appkey123",
                app_secret = "appsecret456",
                secret = "short",
                redirect_uri = "/login",
            })
            ngx.say(ok)
        }
    }
--- response_body
false



=== TEST 4: enable dingtalk-auth plugin
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
                    "plugins": {
                        "dingtalk-auth": {
                            "app_key": "testappkey",
                            "app_secret": "testappsecret",
                            "secret": "my-session-secret",
                            "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                            "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                            "cookie_expires_in": 2,
                            "redirect_uri": "/login"
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
--- response_body
passed



=== TEST 5: no code provided - redirect to redirect_uri
--- request
GET /hello
--- error_code: 302
--- response_headers
Location: /login



=== TEST 6: invalid code - returns 401
--- request
GET /hello?code=invalid_code
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 7: valid code via query param - returns 200
--- request
GET /hello?code=valid_code
--- error_code: 200
--- response_body
hello world



=== TEST 8: valid code via X-DingTalk-Code header - returns 200
--- request
GET /hello
--- more_headers
X-DingTalk-Code: valid_code
--- error_code: 200
--- response_body
hello world



=== TEST 9: cookie session - subsequent requests reuse session
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            -- first request with valid code to obtain session cookie
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                query = { code = "valid_code" },
            })
            assert(res, "request failed: " .. (err or "nil"))
            assert(res.status == 200, "expected 200, got: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- second request using the session cookie (no code needed)
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie },
            })
            assert(res2, "request failed: " .. (err or "nil"))
            assert(res2.status == 200, "expected 200, got: " .. res2.status)

            -- request without cookie redirects again
            local res3, err = httpc:request_uri(uri, { method = "GET" })
            assert(res3, "request failed: " .. (err or "nil"))
            assert(res3.status == 302, "expected 302, got: " .. res3.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 10: cookie expires after cookie_expires_in seconds
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local res, err = httpc:request_uri(uri, {
                method = "GET",
                query = { code = "valid_code" },
            })
            assert(res, "request failed: " .. (err or "nil"))
            assert(res.status == 200, "expected 200, got: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- cookie still valid before expiry
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie },
            })
            assert(res2, "request failed: " .. (err or "nil"))
            assert(res2.status == 200, "expected 200 before expiry, got: " .. res2.status)

            ngx.sleep(3)

            -- cookie should be expired now
            local res3, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie },
            })
            assert(res3, "request failed: " .. (err or "nil"))
            assert(res3.status == 302, "expected 302 after expiry, got: " .. res3.status)

            ngx.say("passed")
        }
    }
--- timeout: 5
--- response_body
passed



=== TEST 11: configure custom code_header and code_query
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
                    "plugins": {
                        "dingtalk-auth": {
                            "app_key": "testappkey",
                            "app_secret": "testappsecret",
                            "secret": "my-session-secret",
                            "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                            "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                            "code_query": "dt_code",
                            "code_header": "X-Custom-DT-Code",
                            "redirect_uri": "/login"
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
--- response_body
passed



=== TEST 12: custom code_query param works
--- pipelined_requests eval
["GET /hello?code=valid_code", "GET /hello?dt_code=valid_code"]
--- error_code eval
[302, 200]



=== TEST 13: custom code_header works
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
[
"X-DingTalk-Code: valid_code",
"X-Custom-DT-Code: valid_code"
]
--- error_code eval
[302, 200]
