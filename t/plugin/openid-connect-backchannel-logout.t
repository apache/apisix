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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

my $stub_idp = <<_EOC_;
    server {
        listen 6724;
        location = /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{"issuer":"http://127.0.0.1:6724","authorization_endpoint":"http://127.0.0.1:6724/authorize","token_endpoint":"http://127.0.0.1:6724/token","jwks_uri":"http://127.0.0.1:6724/jwks","id_token_signing_alg_values_supported":["RS256"]}]])
            }
        }
        location = /jwks {
            content_by_lua_block {
                local pkey = require "resty.openssl.pkey"
                local dump_jwk = require("resty.openssl.auxiliary.jwk").dump_jwk
                local cjson = require "cjson.safe"
                local t = require "lib.test_admin"

                local pub = pkey.new(t.read_file("t/certs/public.pem"))
                local jwk = cjson.decode(dump_jwk(pub, false))
                jwk.kid = "bclkey"
                jwk.alg = "RS256"
                jwk.use = "sig"

                ngx.header.content_type = "application/json"
                ngx.say(cjson.encode({ keys = { jwk } }))
            }
        }
    }
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // '';
    $http_config .= $stub_idp;
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: Minimal backchannel_logout config passes the schema check.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "/logout/backchannel"
                }
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: backchannel_logout is rejected together with bearer_only.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                bearer_only = true,
                backchannel_logout = {
                    path = "/logout/backchannel"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say(err)
        }
    }
--- response_body
backchannel_logout cannot be used with bearer_only



=== TEST 3: storage redis without a redis config and without session.redis is rejected.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "/logout/backchannel",
                    storage = "redis"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say(err)
        }
    }
--- response_body
backchannel_logout.redis is required when backchannel_logout.storage is redis and session.redis is not configured



=== TEST 4: A path that does not start with a slash is rejected.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "logout"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say("rejected")
        }
    }
--- response_body
rejected



=== TEST 5: backchannel_logout is rejected when session_contents omits id_token.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                session_contents = {
                    access_token = true
                },
                backchannel_logout = {
                    path = "/logout/backchannel"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say(err)
        }
    }
--- response_body
backchannel_logout requires session_contents.id_token to be true when session_contents is configured, because session revocation is keyed off the id_token's sid/sub claims



=== TEST 6: Set up a route against the stub IdP with the BCL endpoint enabled.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/bcl"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 7: A valid logout token is accepted and lands in the denylist.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({ jti = "jti-test6", sid = "sess-6" })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.header["Cache-Control"] = res.headers["Cache-Control"]

            local entry = ngx.shared.bcl:get(
                "bcl:sid:http://127.0.0.1:6724#bcl-client#sess-6")
            ngx.say("denylist entry: ", entry ~= nil)
        }
    }
--- response_body
denylist entry: true
--- response_headers
Cache-Control: no-store
--- error_log
OIDC backchannel logout accepted for sid sess-6



=== TEST 8: A replayed jti is rejected on the second delivery.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({ jti = "jti-test7", sid = "sess-7" })

            local res1, err = t.req_self_with_http("/bcl", "POST",
                                                   "logout_token=" .. token)
            if not res1 then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local res2
            res2, err = t.req_self_with_http("/bcl", "POST",
                                             "logout_token=" .. token)
            if not res2 then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("first: ", res1.status)
            ngx.say("second: ", res2.status)
        }
    }
--- response_body
first: 200
second: 400
--- error_log
a logout token with this jti was already received



=== TEST 9: A tampered signature is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({ jti = "jti-test8", sid = "sess-8" })
            -- replace the signature's last two characters with a pair that
            -- is guaranteed to differ from the original
            local tail = token:sub(-2) == "xx" and "yy" or "xx"
            token = token:sub(1, -3) .. tail

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
signature validation failed



=== TEST 10: An unsigned token (alg none) is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"

            local b64 = function(s)
                return ngx.encode_base64(s):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
            end
            local cjson = require "cjson.safe"
            local header = b64(cjson.encode({ alg = "none", typ = "logout+jwt" }))
            local payload = b64(cjson.encode({
                iss = "http://127.0.0.1:6724",
                aud = "bcl-client",
                iat = ngx.time(),
                jti = "jti-test9",
                events = {
                    ["http://schemas.openid.net/event/backchannel-logout"] = {}
                },
                sid = "sess-9",
            }))
            local token = header .. "." .. payload .. "."

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
signature validation failed



=== TEST 11: A route with accept_none_alg true still rejects an unsigned logout token.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "accept_none_alg": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/bcl"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local b64 = function(s)
                return ngx.encode_base64(s):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
            end
            local cjson = require "cjson.safe"
            local header = b64(cjson.encode({ alg = "none", typ = "logout+jwt" }))
            local payload = b64(cjson.encode({
                iss = "http://127.0.0.1:6724",
                aud = "bcl-client",
                iat = ngx.time(),
                jti = "jti-test9a",
                events = {
                    ["http://schemas.openid.net/event/backchannel-logout"] = {}
                },
                sid = "sess-9a",
            }))
            local token = header .. "." .. payload .. "."

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status

            local entry = ngx.shared.bcl:get(
                "bcl:sid:http://127.0.0.1:6724#bcl-client#sess-9a")
            ngx.say("denylist entry: ", entry ~= nil)
        }
    }
--- response_body
denylist entry: false
--- error_code: 400
--- error_log
signature validation failed



=== TEST 12: A token without the back-channel logout event is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({
                jti = "jti-test10",
                sid = "sess-10",
                events = bcl.OMIT,
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
events claim does not contain the back-channel logout event



=== TEST 13: A token carrying a nonce is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({
                jti = "jti-test11",
                nonce = "forged",
                sid = "sess-11",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
nonce claim is prohibited in a logout token



=== TEST 14: A token with neither sub nor sid is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({ jti = "jti-test12" })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
either a sub or a sid claim is required



=== TEST 15: A token without a jti is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({ sid = "sess-13" })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
jti claim is missing



=== TEST 16: A token with a stale iat is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({
                iat = ngx.time() - 1200,
                jti = "jti-test14",
                sid = "sess-14",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
iat is outside the acceptance window



=== TEST 17: A token whose aud names another client is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local token = bcl.sign({
                aud = "some-other-client",
                jti = "jti-test15",
                sid = "sess-15",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
aud does not contain the client_id



=== TEST 18: A POST without a logout_token is rejected.
--- request
POST /bcl
foo=bar
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400



=== TEST 19: A non-POST request to the back-channel logout endpoint returns 405 with an Allow header.
--- request
GET /bcl
--- error_code: 405
--- response_headers
Allow: POST



=== TEST 20: Set up the Keycloak route and register the BCL URL at the client.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local keycloak = require "lib.keycloak"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/logout/backchannel"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say(body)

            local token, err = keycloak.get_admin_token()
            if not token then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local url = "http://127.0.0.1:" .. ngx.var.server_port ..
                        "/logout/backchannel"
            local ok
            ok, err = keycloak.set_backchannel_logout(token, url, true)
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("bcl configured")
        }
    }
--- response_body
passed
bcl configured



=== TEST 21: The session is rejected after the IdP delivers a back-channel logout (sid).
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local keycloak = require "lib.keycloak"

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"

            -- Absorb any stale pooled connection at Keycloak before the
            -- delivery this test asserts on.
            local pok, perr = keycloak.prime_backchannel_logout(uri)
            if not pok then
                ngx.status = 500
                ngx.say(perr)
                return
            end

            local res, err = keycloak.login_keycloak(uri,
                                                     "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = keycloak.concatenate_cookies(
                res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("authenticated: ", res.status)

            local token, terr = keycloak.get_admin_token()
            if not token then
                ngx.status = 500
                ngx.say(terr)
                return
            end
            local ok, lerr = keycloak.logout_user(token, "teacher@gmail.com")
            if not ok then
                ngx.status = 500
                ngx.say(lerr)
                return
            end
            ngx.say("logout: done")
            -- Keycloak delivers the BCL POST while processing the logout;
            -- the sleep absorbs scheduling jitter.
            ngx.sleep(1)

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("after logout: ", res.status)
        }
    }
--- timeout: 15
--- response_body
authenticated: 200
logout: done
after logout: 302
--- error_log
OIDC backchannel logout accepted for sid
OIDC session revoked by backchannel logout



=== TEST 22: With unauth_action deny, a revoked session gets 401.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = require("lib.test_admin").test
            local keycloak = require "lib.keycloak"

            local route_tpl = [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                %s
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/logout/backchannel"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]

            -- Login must happen under the default auth action; deny would
            -- answer 401 instead of driving the login redirect.
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                                 string.format(route_tpl, ""))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"

            -- Absorb any stale pooled connection at Keycloak before the
            -- delivery this test asserts on.
            local pok, perr = keycloak.prime_backchannel_logout(uri)
            if not pok then
                ngx.status = 500
                ngx.say(perr)
                return
            end

            local res, err = keycloak.login_keycloak(uri,
                                                     "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = keycloak.concatenate_cookies(
                res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("authenticated: ", res.status)

            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                           string.format(route_tpl,
                                         '"unauth_action": "deny",'))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local token, terr = keycloak.get_admin_token()
            if not token then
                ngx.status = 500
                ngx.say(terr)
                return
            end
            local ok, lerr = keycloak.logout_user(token, "teacher@gmail.com")
            if not ok then
                ngx.status = 500
                ngx.say(lerr)
                return
            end
            ngx.say("logout: done")
            ngx.sleep(1)

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("after logout: ", res.status)
        }
    }
--- timeout: 15
--- response_body
authenticated: 200
logout: done
after logout: 401
--- error_log
OIDC backchannel logout accepted for sid
OIDC session revoked by backchannel logout



=== TEST 23: A sub-only logout kills the session; a later login survives.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = require("lib.test_admin").test
            local keycloak = require "lib.keycloak"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/logout/backchannel"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local token, terr = keycloak.get_admin_token()
            if not token then
                ngx.status = 500
                ngx.say(terr)
                return
            end
            local url = "http://127.0.0.1:" .. ngx.var.server_port ..
                        "/logout/backchannel"
            -- session required off: the logout token carries only sub.
            local ok, serr = keycloak.set_backchannel_logout(token, url, false)
            if not ok then
                ngx.status = 500
                ngx.say(serr)
                return
            end

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"

            -- Absorb any stale pooled connection at Keycloak before the
            -- delivery this test asserts on.
            local pok, perr = keycloak.prime_backchannel_logout(uri)
            if not pok then
                ngx.status = 500
                ngx.say(perr)
                return
            end

            local res, err = keycloak.login_keycloak(uri,
                                                     "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = keycloak.concatenate_cookies(
                res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("authenticated: ", res.status)

            local lerr
            ok, lerr = keycloak.logout_user(token, "teacher@gmail.com")
            if not ok then
                ngx.status = 500
                ngx.say(lerr)
                return
            end
            ngx.say("logout: done")
            ngx.sleep(1)

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("after logout: ", res.status)

            -- The sub rule kills sessions authenticated at or before the
            -- revocation's second; move the new login past it.
            ngx.sleep(1.5)

            res, err = keycloak.login_keycloak(uri,
                                               "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end
            cookie_str = keycloak.concatenate_cookies(res.headers['Set-Cookie'])
            redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                           res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("re-login: ", res.status)
        }
    }
--- timeout: 25
--- response_body
authenticated: 200
logout: done
after logout: 302
re-login: 200
--- error_log
OIDC backchannel logout accepted for sub
OIDC session revoked by backchannel logout



=== TEST 24: With storage redis, an accepted logout token lands in redis.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/bcl",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 6379
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- unique per run: the jti replay guard lives in redis,
            -- which outlives the test nginx instances
            local token = bcl.sign({
                jti = "jti-test21-" .. ngx.now(),
                sid = "sess-21",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status

            local resty_redis = require "resty.redis"
            local red = resty_redis:new()
            local ok, cerr = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.status = 500
                ngx.say(cerr)
                return
            end
            local v = red:get("bcl:bcl:sid:http://127.0.0.1:6724#bcl-client#sess-21")
            ngx.say("redis entry: ", v ~= ngx.null)
        }
    }
--- response_body
redis entry: true
--- error_log
OIDC backchannel logout accepted for sid sess-21



=== TEST 25: storage redis without an own redis block falls back to session.redis.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 6379
                                    }
                                },
                                "backchannel_logout": {
                                    "path": "/bcl",
                                    "storage": "redis"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- unique per run: the jti replay guard lives in redis,
            -- which outlives the test nginx instances
            local token = bcl.sign({
                jti = "jti-test22-" .. ngx.now(),
                sid = "sess-22",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status

            local resty_redis = require "resty.redis"
            local red = resty_redis:new()
            local ok, cerr = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.status = 500
                ngx.say(cerr)
                return
            end
            local v = red:get(
                "sessions:bcl:sid:http://127.0.0.1:6724#bcl-client#sess-22")
            ngx.say("redis entry: ", v ~= ngx.null)
        }
    }
--- response_body
redis entry: true
--- error_log
OIDC backchannel logout accepted for sid sess-22



=== TEST 26: The endpoint answers 400 when the redis store is unreachable.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/bcl",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 1979
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local token = bcl.sign({ jti = "jti-test23", sid = "sess-23" })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_code: 400
--- error_log
OIDC backchannel logout store failed



=== TEST 27: A request with the store down gets 503 and the session is kept.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = require("lib.test_admin").test
            local keycloak = require "lib.keycloak"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/logout/backchannel",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 1979
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = keycloak.login_keycloak(uri,
                                                     "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local cookie_str = keycloak.concatenate_cookies(
                res.headers['Set-Cookie'])

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("first request: ", res.status)

            local set_cookie = res.headers["Set-Cookie"] or ""
            if type(set_cookie) == "table" then
                set_cookie = table.concat(set_cookie, "; ")
            end
            ngx.say("session destroyed: ",
                    set_cookie:find("01 Jan 1970", 1, true) ~= nil)

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["Cookie"] = cookie_str }
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("second request: ", res.status)
        }
    }
--- timeout: 15
--- response_body
first request: 503
session destroyed: false
second request: 503
--- error_log
OIDC backchannel logout store failed



=== TEST 28: With storage redis, session.absolute_timeout 0 still falls back to a usable TTL.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    "absolute_timeout": 0
                                },
                                "backchannel_logout": {
                                    "path": "/bcl",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 6379
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- unique per run: the jti replay guard lives in redis,
            -- which outlives the test nginx instances
            local token = bcl.sign({
                jti = "jti-test27-" .. ngx.now(),
                sid = "sess-27",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status

            local resty_redis = require "resty.redis"
            local red = resty_redis:new()
            local ok, cerr = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.status = 500
                ngx.say(cerr)
                return
            end
            local v = red:get("bcl:bcl:sid:http://127.0.0.1:6724#bcl-client#sess-27")
            ngx.say("redis entry: ", v ~= ngx.null)
            local ttl = red:ttl("bcl:bcl:sid:http://127.0.0.1:6724#bcl-client#sess-27")
            ngx.say("redis ttl positive: ", ttl ~= nil and ttl > 0)
        }
    }
--- response_body
redis entry: true
redis ttl positive: true
--- error_log
OIDC backchannel logout accepted for sid sess-27



=== TEST 29: With storage redis, the denylist entry stores the token's iat, not receipt time.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local bcl = require "lib.backchannel_logout"

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:6724/.well-known/openid-configuration",
                                "client_id": "bcl-client",
                                "client_secret": "dummy-not-used-by-the-endpoint",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "backchannel_logout": {
                                    "path": "/bcl",
                                    "storage": "redis",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 6379
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- Clearly earlier than receipt, but inside the iat acceptance slack.
            local past = ngx.time() - 60
            local token = bcl.sign({
                iat = past,
                jti = "jti-test28-" .. ngx.now(),
                sub = "sub-28",
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status

            local resty_redis = require "resty.redis"
            local red = resty_redis:new()
            local ok, cerr = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.status = 500
                ngx.say(cerr)
                return
            end
            local v = red:get("bcl:bcl:sub:http://127.0.0.1:6724#bcl-client#sub-28")
            ngx.say("stored value equals token iat: ", tonumber(v) == past)
        }
    }
--- response_body
stored value equals token iat: true
--- error_log
OIDC backchannel logout accepted for sub sub-28
