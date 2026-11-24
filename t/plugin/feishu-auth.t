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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_init_by_lua = <<_EOC_;
    local server = require("lib.server")
    server.token = function()
        local json = require("cjson")
        local headers = ngx.req.get_headers()
        ngx.log(ngx.INFO, ngx.var.request_uri, " receive headers: ", json.encode(headers))

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        ngx.log(ngx.INFO, ngx.var.request_uri, " payload: ", data)

        local payload = json.decode(data)

        if payload.code ~= "passed" then
            ngx.status = 400
            ngx.say([[{"code": 20051, "error_description": "Unauthorized"}]])
            return
        end

        ngx.log(ngx.INFO, ngx.var.request_uri, " payload: ", data)

        local resp_payload = [[
{
    "code": 0,
    "expires_in": 7200,
    "access_token": "85b8b7665c4c3bc5bd91d8e6cb6594b7",
    "token_type": "Bearer"
}
        ]]

        ngx.say(resp_payload)
    end

    server.userinfo = function()
        local json = require("cjson")
        local headers = ngx.req.get_headers()
        ngx.log(ngx.INFO, ngx.var.request_uri, " receive headers: ", json.encode(headers))

        local resp_payload = [[
{
  "code": 0,
  "data": {
    "avatar_big": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4be",
    "avatar_middle": "https://s1-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba4",
    "avatar_thumb": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba",
    "avatar_url": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba4g",
    "en_name": "jack",
    "name": "jack",
    "open_id": "ou_8fc70d9ea27111749a71eb",
    "tenant_key": "1224d18e8d",
    "union_id": "on_c249ec29c9d6"
  },
  "msg": "success"
}
        ]]

        ngx.say(resp_payload)
    end

    server.hello_echo = function()
        -- echo back the X-Userinfo header value so tests can assert it was cleared
        ngx.say(ngx.req.get_headers()["x-userinfo"] or "none")
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);


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
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
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



=== TEST 2: missing code, redirect carries a state
--- request
GET /hello
--- error_code: 302
--- response_headers_like
Location: /echo\?state=[0-9a-f]{32}



=== TEST 3: query code without a state is rejected
--- request
GET /hello?code=passed
--- error_code: 401
--- response_body
{"message":"Invalid state"}



=== TEST 4: query code with a state not bound to the session is rejected
--- request
GET /hello?code=passed&state=deadbeefdeadbeefdeadbeefdeadbeef
--- error_code: 401
--- response_body
{"message":"Invalid state"}



=== TEST 5: invalid code with a valid state
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "invalid")
            assert(res, err)
            assert(res.status == 401, "expected 401, got " .. res.status)
            ngx.print(res.body)
        }
    }
--- response_body
{"message":"Invalid authorization code"}



=== TEST 6: valid code with the state bound to the session
--- config
    location /t {
        content_by_lua_block {
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "passed")
            assert(res, err)
            assert(res.status == 200, "expected 200, got " .. res.status)
            ngx.print(res.body)
        }
    }
--- response_body
hello world



=== TEST 7: a state from one session cannot be used by another session
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
                query = {code = "passed", state = state_a},
                headers = {["Cookie"] = cookie_b},
            }))
            assert(res.status == 401, "expected 401, got " .. res.status)
            assert(not res.headers["Set-Cookie"],
                   "invalid state must not clear the pending session")

            -- session B with its own state still works
            local res2 = assert(httpc:request_uri(uri, {
                method = "GET",
                query = {code = "passed", state = state_b},
                headers = {["Cookie"] = cookie_b},
            }))
            assert(res2.status == 200, "expected 200, got " .. res2.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: X-Feishu-Code with invalid code
--- request
GET /hello
--- more_headers
X-Feishu-Code: invalid
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 9: X-Feishu-Code header
--- request
GET /hello
--- more_headers
X-Feishu-Code: passed
--- error_code: 200
--- response_body
hello world



=== TEST 10: check cookie
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "passed")
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



=== TEST 11: cookie expire
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "passed")
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



=== TEST 12: specify header and query and redirect_uri
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
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
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



=== TEST 13: specify query
--- config
    location /t {
        content_by_lua_block {
            local httpc = require("resty.http").new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            -- the default query name is not the configured one, so no code is seen
            local res = assert(httpc:request_uri(uri, {
                method = "GET",
                query = {code = "passed"},
            }))
            assert(res.status == 302, "expected 302, got " .. res.status)

            local oauth = require("lib.oauth_login")
            local res2, err = oauth.login(ngx.var.server_port, "/hello",
                                             "passed", "custom_code")
            assert(res2, err)
            assert(res2.status == 200, "expected 200, got " .. res2.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: specify header
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
[
"X-Feishu-Code: passed",
"Custom-Feishu-Code: passed"
]
--- error_code eval
[302, 200]



=== TEST 15: secret_fallbacks allows session created with old secret after key rotation
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local t = require("lib.test_admin").test

            -- step 1: create route with secret-v1, no fallbacks
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "secret-v1",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            assert(code <= 201, "setup v1 failed: " .. tostring(code))

            -- step 2: authenticate with secret-v1 and capture session cookie
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local oauth = require("lib.oauth_login")
            local res, err = oauth.login(ngx.var.server_port, "/hello", "passed")
            assert(res, err)
            assert(res.status == 200, "expected 200, got " .. res.status)
            local old_cookie = res.headers["Set-Cookie"]
            assert(old_cookie, "expected Set-Cookie from v1")

            -- step 3: rotate to secret-v2 with secret-v1 in secret_fallbacks
            local code2, body2 = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "secret-v2",
                            "secret_fallbacks": ["secret-v1"],
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            assert(code2 <= 201, "setup v2 failed: " .. tostring(code2))

            -- step 4: old cookie should still work via fallback
            local res2, err2 = httpc:request_uri(uri, {
                method = "GET",
                headers = {["Cookie"] = old_cookie},
            })
            assert(res2, err2)
            assert(res2.status == 200,
                "old cookie should be accepted via fallback, got " .. res2.status)

            -- step 5: remove fallbacks; old cookie should no longer work
            local code3, body3 = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "secret-v2",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            assert(code3 <= 201, "setup v2-no-fallback failed: " .. tostring(code3))

            local res3, err3 = httpc:request_uri(uri, {
                method = "GET",
                headers = {["Cookie"] = old_cookie},
            })
            assert(res3, err3)
            assert(res3.status == 302,
                "old cookie should be rejected without fallback, got " .. res3.status)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 16: forged X-Userinfo header does not bypass authentication
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local t = require("lib.test_admin").test

            -- restore route to a simple config
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret-xyz",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            assert(code <= 201, "setup failed: " .. tostring(code))

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            -- forged X-Userinfo without a session cookie must be rejected
            local res1, err1 = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["X-Userinfo"] = ngx.encode_base64('{"open_id":"forged","name":"hacker"}'),
                },
            })
            assert(res1, err1)
            assert(res1.status == 302,
                "forged X-Userinfo without cookie should be rejected, got " .. res1.status)

            -- obtain a legitimate session cookie
            local oauth = require("lib.oauth_login")
            local res2, err2 = oauth.login(ngx.var.server_port, "/hello", "passed")
            assert(res2, err2)
            assert(res2.status == 200, "expected 200 on auth, got " .. res2.status)
            local cookie = res2.headers["Set-Cookie"]
            assert(cookie, "expected Set-Cookie after auth")

            -- valid cookie + forged X-Userinfo: request succeeds only due to the cookie
            local res3, err3 = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                    ["X-Userinfo"] = ngx.encode_base64('{"open_id":"forged","name":"hacker"}'),
                },
            })
            assert(res3, err3)
            assert(res3.status == 200,
                "valid cookie should be accepted regardless of forged header, got " .. res3.status)

            -- create a route with set_userinfo_header=false to verify the forged header
            -- is cleared and not forwarded to upstream
            local code2, body2 = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret-xyz",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo",
                            "set_userinfo_header": false
                        }
                    },
                    "uri": "/hello-echo"
                }]]
            )
            assert(code2 <= 201, "setup echo route failed: " .. tostring(code2))

            local echo_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello-echo"
            local forged = ngx.encode_base64('{"open_id":"forged","name":"hacker"}')

            -- with set_userinfo_header=false, upstream must not receive any X-Userinfo
            local res4, err4 = httpc:request_uri(echo_uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                    ["X-Userinfo"] = forged,
                },
            })
            assert(res4, err4)
            assert(res4.status == 200,
                "expected 200 on echo route, got " .. res4.status)
            assert(res4.body == "none\n",
                "forged X-Userinfo must not reach upstream, got: " .. (res4.body or "nil"))

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 17: secret_fallbacks values are encrypted in etcd
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "feishu-auth": {
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret-key-v2",
                            "secret_fallbacks": ["my-secret-key-v1"],
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- Admin API should return decrypted values
            local code2, _, res2 = t('/apisix/admin/routes/1', ngx.HTTP_GET)
            assert(code2 == 200, "admin get route failed: " .. tostring(code2))
            res2 = json.decode(res2)
            local conf = res2.value.plugins["feishu-auth"]
            ngx.say("admin secret_fallbacks[1]: ", conf.secret_fallbacks[1])

            -- etcd should store encrypted values
            local etcd = require("apisix.core.etcd")
            local etcd_res = assert(etcd.get('/routes/1'))
            local etcd_conf = etcd_res.body.node.value.plugins["feishu-auth"]
            assert(etcd_conf.secret_fallbacks and etcd_conf.secret_fallbacks[1],
                "expected secret_fallbacks[1] in etcd payload")
            ngx.say("etcd secret_fallbacks[1] encrypted: ",
                etcd_conf.secret_fallbacks[1] ~= "my-secret-key-v1")
        }
    }
--- response_body
admin secret_fallbacks[1]: my-secret-key-v1
etcd secret_fallbacks[1] encrypted: true



=== TEST 18: a session from another Feishu application is rejected
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
                    "feishu-auth": {
                        "app_id": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://a.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "redirect_uri": "/echo"
                    }
                },
                "uri": "/hello"
            }]])
            assert(code <= 201, "setup application A failed: " .. tostring(code))

            local res = oauth.login(port, "/hello", "passed")
            assert(res and res.status == 200, "application A login failed")
            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "application A did not issue a session cookie")

            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "feishu-auth": {
                        "app_id": "application-b",
                        "app_secret": "secret-b",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://b.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "redirect_uri": "/echo"
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
                    "feishu-auth": {
                        "app_id": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://a.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/other-userinfo",
                        "redirect_uri": "/echo"
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
                cookie_name = "feishu_session",
                audience = "default",
                compression_threshold = 0,
            })
            legacy:set("userinfo", '{"open_id":"legacy-user","padding":"'
                       .. string.rep("x", 5000) .. '"}')
            assert(legacy:save())
            local legacy_headers = ngx.header["Set-Cookie"]
            assert(type(legacy_headers) == "table",
                "the legacy fixture must contain chunked cookies")
            local legacy_pairs = {}
            for _, header in ipairs(legacy_headers) do
                table.insert(legacy_pairs, header:match("^[^;]+"))
            end
            assert(#legacy_pairs >= 2, "the legacy fixture must have multiple chunks")
            ngx.header["Set-Cookie"] = nil

            local function assert_expired(request_cookie, expected_pairs, label)
                local response = assert(http.new():request_uri(base .. "/hello", {
                    headers = {["Cookie"] = request_cookie},
                }))
                assert(response.status == 302,
                    "a legacy default-audience session must authenticate again, got "
                    .. tostring(response.status) .. " for " .. label)

                local cleared = response.headers["Set-Cookie"]
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
                for _, pair in ipairs(expected_pairs) do
                    local name = pair:match("^([^=]+)=")
                    assert(expired[name], "legacy cookie was not expired: " .. name)
                end
            end

            assert_expired(table.concat(legacy_pairs, "; "), legacy_pairs, "complete chain")
            local main_name = legacy_pairs[1]:match("^([^=]+)=")
            local second_name = legacy_pairs[2]:match("^([^=]+)=")
            local third_name = main_name .. "3"

            local function assert_one_expired(request_cookie, expected_name)
                local response = assert(http.new():request_uri(base .. "/hello", {
                    headers = {Cookie = request_cookie},
                }))
                assert(response.status == 302, "expected 302, got " .. response.status)
                local cleared = response.headers["Set-Cookie"]
                if type(cleared) == "string" then
                    cleared = {cleared}
                end
                local matched = false
                for _, header in ipairs(cleared) do
                    if header:find(expected_name .. "=;", 1, true)
                       and header:find("Max-Age=0", 1, true) then
                        matched = true
                    end
                end
                assert(matched, "legacy cookie was not expired: " .. expected_name)
            end

            assert_one_expired(second_name .. "=isolated", second_name)
            assert_one_expired(main_name .. "=main; " .. third_name .. "=sparse", third_name)
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
                    "feishu-auth": {
                        "app_id": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://a.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "redirect_uri": "/echo"%s
                    }
                },
                "uri": "/hello"
            }]]

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                           string.format(route, ""))
            assert(code <= 201, "setup default cookie failed: " .. tostring(code))
            local res = oauth.login(port, "/hello", "passed")
            assert(res and res.status == 200, "login with default cookie failed")
            local cookie = res.headers["Set-Cookie"]
            assert(cookie and cookie:find("; Secure", 1, true),
                "default session cookie must carry Secure")
            local secure_cookie_name = cookie:match("^([^=]+)=")

            code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                     string.format(route, ',"cookie_secure": false'))
            assert(code <= 201, "setup insecure cookie failed: " .. tostring(code))
            res = oauth.login(port, "/hello", "passed")
            assert(res and res.status == 200, "login with explicit opt-out failed")
            cookie = res.headers["Set-Cookie"]
            assert(cookie and not cookie:find("; Secure", 1, true),
                "cookie_secure=false must omit Secure")
            local insecure_cookie_name = cookie:match("^([^=]+)=")
            assert(secure_cookie_name ~= insecure_cookie_name,
                "different Secure policies must not share a cookie name")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed




=== TEST 20: application cookies isolate Secure attributes and absolute lifetimes
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
                    "feishu-auth": {
                        "app_id": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://a.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "cookie_expires_in": 300,
                        "redirect_uri": "/echo"
                    }
                },
                "uri": "/hello"
            }]])
            assert(code <= 201, "setup application A failed: " .. tostring(code))

            local res = oauth.login(port, "/hello", "passed")
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
                    "feishu-auth": {
                        "app_id": "application-b",
                        "app_secret": "secret-b",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://b.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "cookie_expires_in": 300,
                        "cookie_secure": false,
                        "redirect_uri": "/echo"
                    },
                    "proxy-rewrite": {"uri": "/hello"}
                },
                "uri": "/hello-other"
            }]])
            assert(code <= 201, "setup application B failed: " .. tostring(code))

            local before_b = ngx.time()
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
                query = {code = "passed", state = state},
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
                "http://127.0.0.1:1980/token",
                "http://127.0.0.1:1980/userinfo",
                "false",
            }, "\0"))
            local fingerprint = require("resty.string").to_hex(sha256:final())
            ngx.req.set_header("Cookie", pair_b)
            local opened_b = require("resty.session").open({
                secret = "shared-session-secret",
                cookie_name = name_b,
                audience = "feishu-auth:" .. fingerprint,
                cookie_secure = false,
                absolute_timeout = 300,
            })
            local creation_time = opened_b:get_property("creation_time")
            assert(creation_time and creation_time >= before_b,
                "application B inherited application A's creation time: "
                .. tostring(creation_time))

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



=== TEST 21: failed application login does not destroy another application's session
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
                    "feishu-auth": {
                        "app_id": "application-a",
                        "app_secret": "secret-a",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://a.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/userinfo",
                        "redirect_uri": "/echo"
                    }
                },
                "uri": "/hello"
            }]])
            assert(code <= 201, "setup application A failed: " .. tostring(code))
            local res = oauth.login(port, "/hello", "passed")
            assert(res and res.status == 200, "application A login failed")
            local cookie_a = res.headers["Set-Cookie"]
            local pair_a = cookie_a:match("^[^;]+")
            local name_a = pair_a:match("^([^=]+)=")

            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "methods": ["GET"],
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                "plugins": {
                    "feishu-auth": {
                        "app_id": "application-b",
                        "app_secret": "secret-b",
                        "secret": "shared-session-secret",
                        "auth_redirect_uri": "https://b.example.com/callback",
                        "access_token_url": "http://127.0.0.1:1980/token",
                        "userinfo_url": "http://127.0.0.1:1980/other-userinfo",
                        "cookie_secure": false,
                        "redirect_uri": "/echo"
                    }
                },
                "uri": "/hello-other-failure"
            }]])
            assert(code <= 201, "setup application B failed: " .. tostring(code))

            local begin_b = assert(http.new():request_uri(base .. "/hello-other-failure", {
                headers = {Cookie = pair_a}
            }))
            assert(begin_b.status == 302)
            local pending_b = begin_b.headers["Set-Cookie"]
            local pair_b = pending_b:match("^[^;]+")
            local name_b = pair_b:match("^([^=]+)=")
            assert(name_a ~= name_b,
                "a failed application must not destroy another application's cookie")

            local state = begin_b.headers["Location"]:match("state=([0-9a-f]+)")
            local callback_b = assert(http.new():request_uri(base .. "/hello-other-failure", {
                query = {code = "passed", state = state},
                headers = {Cookie = pair_a .. "; " .. pair_b}
            }))
            assert(callback_b.status == 401,
                "application B userinfo failure must reject the login")
            local destroyed_b = callback_b.headers["Set-Cookie"]
            assert(destroyed_b:match("^([^=]+)=") == name_b)
            assert(destroyed_b:find("Max-Age=0", 1, true),
                "failed application login must clear only its own cookie")

            local replay_a = assert(http.new():request_uri(base .. "/hello", {
                headers = {Cookie = pair_a}
            }))
            assert(replay_a.status == 200,
                "application B failure must not log out application A")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
unexpected http response status from feishu: 404
