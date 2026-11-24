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

        location /dt-echo {
            content_by_lua_block {
                -- echo back the received X-Userinfo header so tests can assert it
                ngx.say(ngx.req.get_headers()["x-userinfo"] or "none")
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
            ngx.say(err)
        }
    }
--- response_body
false
property "app_key" is required



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
            ngx.say(err)
        }
    }
--- response_body
false
property "secret" validation failed: string too short, expected at least 8, got 5



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



=== TEST 5: no code provided - redirect to redirect_uri with a state
--- request
GET /hello
--- error_code: 302
--- response_headers_like
Location: /login\?state=[0-9a-f]{32}



=== TEST 6: query code without a state is rejected
--- request
GET /hello?code=valid_code
--- error_code: 401
--- response_body
{"message":"Invalid state"}



=== TEST 7: query code with a state not bound to the session is rejected
--- request
GET /hello?code=valid_code&state=deadbeefdeadbeefdeadbeefdeadbeef
--- error_code: 401
--- response_body
{"message":"Invalid state"}



=== TEST 8: invalid code with a valid state - returns 401
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "invalid_code")
            assert(res, err)
            assert(res.status == 401, "expected 401, got " .. res.status)
            ngx.print(res.body)
        }
    }
--- response_body
{"message":"Invalid authorization code"}



=== TEST 9: valid code via query param - returns 200
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "valid_code")
            assert(res, err)
            assert(res.status == 200, "expected 200, got " .. res.status)
            ngx.print(res.body)
        }
    }
--- response_body
hello world



=== TEST 10: a state from one session cannot be used by another session
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local httpc = require("resty.http").new()
            local port = ngx.var.server_port
            local uri = "http://127.0.0.1:" .. port .. "/hello"

            local cookie_a, state_a, err_a = oauth.begin(port, "/hello")
            assert(cookie_a, err_a)
            local cookie_b, state_b, err_b = oauth.begin(port, "/hello")
            assert(cookie_b, err_b)
            assert(state_a ~= state_b, "states must not repeat across sessions")

            -- session B presented with session A's state: this is the shape of an
            -- injected code, and it must not authenticate
            local res = assert(httpc:request_uri(uri, {
                method = "GET",
                query = {code = "valid_code", state = state_a},
                headers = {["Cookie"] = cookie_b},
            }))
            assert(res.status == 401, "expected 401, got " .. res.status)
            assert(not res.headers["Set-Cookie"],
                   "invalid state must not clear the pending session")

            -- session B with its own state still works
            local res2 = assert(httpc:request_uri(uri, {
                method = "GET",
                query = {code = "valid_code", state = state_b},
                headers = {["Cookie"] = cookie_b},
            }))
            assert(res2.status == 200, "expected 200, got " .. res2.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 11: valid code via X-DingTalk-Code header - returns 200
--- request
GET /hello
--- more_headers
X-DingTalk-Code: valid_code
--- error_code: 200
--- response_body
hello world



=== TEST 12: cookie session - subsequent requests reuse session
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            -- first request with valid code to obtain session cookie
            local res, err = require("lib.oauth_login")
                                .login(ngx.var.server_port, "/hello", "valid_code")
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



=== TEST 13: cookie expires after cookie_expires_in seconds
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local res, err = require("lib.oauth_login")
                                .login(ngx.var.server_port, "/hello", "valid_code")
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



=== TEST 14: configure custom code_header and code_query
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



=== TEST 15: custom code_query param works
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local httpc = require("resty.http").new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            -- the default query name is not the configured one, so no code is seen
            local res = assert(httpc:request_uri(uri, {
                method = "GET",
                query = {code = "valid_code"},
            }))
            assert(res.status == 302, "expected 302, got " .. res.status)

            local res2, err = oauth.login(ngx.var.server_port, "/hello",
                                          "valid_code", "dt_code")
            assert(res2, err)
            assert(res2.status == 200, "expected 200, got " .. res2.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 16: custom code_header works
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
[
"X-DingTalk-Code: valid_code",
"X-Custom-DT-Code: valid_code"
]
--- error_code eval
[302, 200]



=== TEST 17: client-supplied X-Userinfo is not forwarded to upstream
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local t = require("lib.test_admin").test
            local forged = ngx.encode_base64('{"userid":"admin","name":"forged"}')

            -- restore route 1 to a clean config and obtain a legitimate cookie
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dingtalk-auth": {
                            "app_key": "testappkey",
                            "app_secret": "testappsecret",
                            "secret": "my-session-secret",
                            "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                            "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                            "redirect_uri": "/login"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            assert(code <= 201, "setup route 1 failed: " .. tostring(code))

            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local res, err = require("lib.oauth_login")
                                .login(ngx.var.server_port, "/hello", "valid_code")
            assert(res, err)
            assert(res.status == 200, "expected 200 on auth, got " .. res.status)
            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "expected Set-Cookie after auth")

            -- forged X-Userinfo without a cookie must not bypass authentication
            local res1, err1 = httpc:request_uri(base .. "/hello", {
                method = "GET",
                headers = {["X-Userinfo"] = forged},
            })
            assert(res1, err1)
            assert(res1.status == 302,
                "forged X-Userinfo without cookie should redirect, got " .. res1.status)

            -- route with set_userinfo_header=false: upstream must receive no X-Userinfo,
            -- even when the client supplies a forged one alongside a valid cookie
            local code2 = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:10421": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dingtalk-auth": {
                            "app_key": "testappkey",
                            "app_secret": "testappsecret",
                            "secret": "my-session-secret",
                            "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                            "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                            "set_userinfo_header": false,
                            "redirect_uri": "/login"
                        }
                    },
                    "uri": "/dt-echo-off"
                }]]
            )
            assert(code2 <= 201, "setup route 2 failed: " .. tostring(code2))

            local res2, err2 = httpc:request_uri(base .. "/dt-echo-off", {
                method = "GET",
                headers = {["Cookie"] = cookie, ["X-Userinfo"] = forged},
            })
            assert(res2, err2)
            assert(res2.status == 200, "expected 200 on echo route, got " .. res2.status)
            assert(res2.body == "none\n",
                "forged X-Userinfo must not reach upstream, got: " .. (res2.body or "nil"))

            -- route with set_userinfo_header=true: the forged value is overwritten
            -- with the verified user info, never forwarded as-is
            local code3 = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:10421": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dingtalk-auth": {
                            "app_key": "testappkey",
                            "app_secret": "testappsecret",
                            "secret": "my-session-secret",
                            "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                            "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                            "set_userinfo_header": true,
                            "redirect_uri": "/login"
                        }
                    },
                    "uri": "/dt-echo-on"
                }]]
            )
            assert(code3 <= 201, "setup route 3 failed: " .. tostring(code3))

            local res3, err3 = httpc:request_uri(base .. "/dt-echo-on", {
                method = "GET",
                headers = {["Cookie"] = cookie, ["X-Userinfo"] = forged},
            })
            assert(res3, err3)
            assert(res3.status == 200, "expected 200 on echo route, got " .. res3.status)
            assert(res3.body ~= forged .. "\n",
                "forged X-Userinfo must be overwritten, got: " .. (res3.body or "nil"))
            assert(res3.body ~= "none\n",
                "verified X-Userinfo should be set, got: " .. (res3.body or "nil"))

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: a session from another DingTalk application is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local t = require("lib.test_admin").test
            local oauth = require("lib.oauth_login")
            local port = ngx.var.server_port
            local base = "http://127.0.0.1:" .. port

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "redirect_uri": "/login"
                    }
                },
                "uri": "/hello"
            }]])
            assert(code <= 201, "setup application A failed: " .. tostring(code))

            local res = oauth.login(port, "/hello", "valid_code")
            assert(res and res.status == 200, "application A login failed")
            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "application A did not issue a session cookie")

            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-b",
                        "app_secret": "secret-b",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "redirect_uri": "/login"
                    }
                },
                "uri": "/hello-other"
            }]])
            assert(code <= 201, "setup application B failed: " .. tostring(code))

            local replay = http.new():request_uri(base .. "/hello-other", {
                headers = {["Cookie"] = cookie},
            })
            assert(replay, "failed to replay application A cookie")
            assert(replay.status == 302,
                "application B must restart login instead of accepting application A session, got "
                .. replay.status)

            code = t('/apisix/admin/routes/3', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/other-userinfo",
                        "redirect_uri": "/login"
                    }
                },
                "uri": "/hello-other-provider"
            }]])
            assert(code <= 201, "setup alternate Provider failed: " .. tostring(code))

            replay = http.new():request_uri(base .. "/hello-other-provider", {
                headers = {["Cookie"] = cookie},
            })
            assert(replay and replay.status == 302,
                "a changed Provider endpoint must use a different audience")

            local session = require("resty.session")
            local legacy = session.start({
                secret = "shared-session-secret",
                cookie_name = "dingtalk_session",
                audience = "default",
                compression_threshold = 0,
            })
            legacy:set("userinfo", '{"userid":"legacy-user","padding":"'
                       .. string.rep("x", 5000) .. '"}')
            assert(legacy:save())
            local legacy_headers = ngx.header["Set-Cookie"]
            assert(type(legacy_headers) == "table",
                "the legacy fixture must contain chunked cookies")
            local legacy_pairs = {}
            for _, header in ipairs(legacy_headers) do
                table.insert(legacy_pairs, header:match("^[^;]+"))
            end
            ngx.header["Set-Cookie"] = nil
            replay = http.new():request_uri(base .. "/hello", {
                headers = {["Cookie"] = table.concat(legacy_pairs, "; ")},
            })
            assert(replay and replay.status == 302,
                "a legacy default-audience session must authenticate again")

            local cleared = replay.headers["Set-Cookie"]
            if type(cleared) == "string" then
                cleared = {cleared}
            end
            local expired = {}
            for _, header in ipairs(cleared) do
                local name = header:match("^([^=]+)=")
                if name and header:find("Max-Age=0", 1, true) then
                    expired[name] = true
                end
            end
            for _, pair in ipairs(legacy_pairs) do
                local name = pair:match("^([^=]+)=")
                assert(expired[name], "legacy cookie was not expired: " .. name)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 19: session cookie is Secure by default and allows an explicit opt-out
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local oauth = require("lib.oauth_login")
            local port = ngx.var.server_port
            local route = [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "redirect_uri": "/login"%s
                    }
                },
                "uri": "/hello"
            }]]

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                           string.format(route, ""))
            assert(code <= 201, "setup default cookie failed: " .. tostring(code))
            local res = oauth.login(port, "/hello", "valid_code")
            assert(res and res.status == 200, "login with default cookie failed")
            local cookie = res.headers["Set-Cookie"]
            assert(cookie and cookie:find("; Secure", 1, true),
                "default session cookie must carry Secure")

            code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                     string.format(route, ',"cookie_secure": false'))
            assert(code <= 201, "setup insecure cookie failed: " .. tostring(code))
            res = oauth.login(port, "/hello", "valid_code")
            assert(res and res.status == 200, "login with explicit opt-out failed")
            cookie = res.headers["Set-Cookie"]
            assert(cookie and not cookie:find("; Secure", 1, true),
                "cookie_secure=false must omit Secure")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 20: secret_fallbacks keeps an existing session during key rotation
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local t = require("lib.test_admin").test
            local oauth = require("lib.oauth_login")
            local port = ngx.var.server_port
            local uri = "http://127.0.0.1:" .. port .. "/hello"
            local route = [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-a",
                        "app_secret": "secret-a",
                        "secret": "%s",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "redirect_uri": "/login"%s
                    }
                },
                "uri": "/hello"
            }]]

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                           string.format(route, "secret-v1", ""))
            assert(code <= 201, "setup secret-v1 failed: " .. tostring(code))
            local res = oauth.login(port, "/hello", "valid_code")
            assert(res and res.status == 200, "login with secret-v1 failed")
            local old_cookie = res.headers["Set-Cookie"]
            assert(old_cookie, "secret-v1 did not issue a session cookie")

            code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                     string.format(route, "secret-v2", ', "secret_fallbacks": ["secret-v1"]'))
            assert(code <= 201, "setup fallback failed: " .. tostring(code))
            res = http.new():request_uri(uri, {headers = {["Cookie"] = old_cookie}})
            assert(res and res.status == 200,
                "old cookie must be accepted through secret_fallbacks")

            code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                     string.format(route, "secret-v2", ""))
            assert(code <= 201, "removing fallback failed: " .. tostring(code))
            res = http.new():request_uri(uri, {headers = {["Cookie"] = old_cookie}})
            assert(res and res.status == 302,
                "old cookie must be rejected after removing the fallback")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed




=== TEST 21: application cookies isolate Secure attributes and absolute lifetimes
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local t = require("lib.test_admin").test
            local oauth = require("lib.oauth_login")
            local port = ngx.var.server_port
            local base = "http://127.0.0.1:" .. port

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "cookie_expires_in": 300,
                        "redirect_uri": "/login"
                    }
                },
                "uri": "/hello"
            }]])
            assert(code <= 201, "setup application A failed: " .. tostring(code))

            local res = oauth.login(port, "/hello", "valid_code")
            assert(res and res.status == 200, "application A login failed")
            local cookie_a = res.headers["Set-Cookie"]
            assert(cookie_a and cookie_a:find("; Secure", 1, true))
            local pair_a = cookie_a:match("^[^;]+")
            local name_a = pair_a:match("^([^=]+)=")

            ngx.sleep(2)
            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "dingtalk-auth": {
                        "app_key": "application-b",
                        "app_secret": "secret-b",
                        "secret": "shared-session-secret",
                        "access_token_url": "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                        "userinfo_url": "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                        "cookie_expires_in": 300,
                        "cookie_secure": false,
                        "redirect_uri": "/login"
                    },
                    "proxy-rewrite": {"uri": "/hello"}
                },
                "uri": "/hello-other"
            }]])
            assert(code <= 201, "setup application B failed: " .. tostring(code))

            local begin_b = assert(http.new():request_uri(base .. "/hello-other", {
                headers = {Cookie = pair_a}
            }))
            assert(begin_b.status == 302, "application B must start a new login")
            local pending_b = begin_b.headers["Set-Cookie"]
            local pending_pair_b = pending_b:match("^[^;]+")
            local name_b = pending_pair_b:match("^([^=]+)=")
            assert(name_a ~= name_b,
                "applications must not share cookie attributes or creation time")
            assert(not pending_b:find("; Secure", 1, true),
                "application B must not rewrite application A's cookie")

            local state = begin_b.headers["Location"]:match("state=([0-9a-f]+)")
            assert(state, "application B login did not carry state")
            local callback_b = assert(http.new():request_uri(base .. "/hello-other", {
                query = {code = "valid_code", state = state},
                headers = {Cookie = pair_a .. "; " .. pending_pair_b}
            }))
            assert(callback_b.status == 200,
                "application B login failed: " .. callback_b.status)
            local cookie_b = callback_b.headers["Set-Cookie"]
            assert(cookie_b and not cookie_b:find("; Secure", 1, true))
            local pair_b = cookie_b:match("^[^;]+")

            local sha256 = require("resty.sha256"):new()
            sha256:update(table.concat({
                "application-b",
                "http://127.0.0.1:10421/v1.0/oauth2/accessToken",
                "http://127.0.0.1:10421/topapi/v2/user/getuserinfo",
                "false",
            }, "\0"))
            local fingerprint = require("resty.string").to_hex(sha256:final())
            ngx.req.set_header("Cookie", pair_b)
            local opened_b = require("resty.session").open({
                secret = "shared-session-secret",
                cookie_name = name_b,
                audience = "dingtalk-auth:" .. fingerprint,
                cookie_secure = false,
                absolute_timeout = 300,
            })
            local remaining = opened_b:get_property("absolute_timeout")
            assert(remaining and remaining > 298,
                "application B inherited application A's creation time: "
                .. tostring(remaining))

            local replay_a = assert(http.new():request_uri(base .. "/hello", {
                headers = {Cookie = pair_a .. "; " .. pair_b}
            }))
            assert(replay_a.status == 200,
                "application A session must remain valid after application B login")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
