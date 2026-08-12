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



=== TEST 5: Set up a route against the stub IdP with the BCL endpoint enabled.
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



=== TEST 6: A valid logout token is accepted and lands in the denylist.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test6",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-6",
                }
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.say("cache-control: ", res.headers["Cache-Control"])

            local entry = ngx.shared.bcl:get(
                "bcl:sid:http://127.0.0.1:6724#bcl-client#sess-6")
            ngx.say("denylist entry: ", entry ~= nil)
        }
    }
--- response_body
cache-control: no-store
denylist entry: true
--- error_log
OIDC backchannel logout accepted for sid sess-6



=== TEST 7: A replayed jti is rejected on the second delivery.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test7",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-7",
                }
            })

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



=== TEST 8: A tampered signature is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test8",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-8",
                }
            })
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



=== TEST 9: An unsigned token (alg none) is rejected.
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



=== TEST 10: A route with accept_none_alg true still rejects an unsigned logout token.
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
            ngx.say("status: ", res.status)

            local entry = ngx.shared.bcl:get(
                "bcl:sid:http://127.0.0.1:6724#bcl-client#sess-9a")
            ngx.say("denylist entry: ", entry ~= nil)
        }
    }
--- response_body
status: 400
denylist entry: false
--- error_log
signature validation failed



=== TEST 11: A token without the back-channel logout event is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test10",
                    sid = "sess-10",
                }
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



=== TEST 12: A token carrying a nonce is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test11",
                    nonce = "forged",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-11",
                }
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



=== TEST 13: A token with neither sub nor sid is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test12",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                }
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
either a sub or a sid claim is required



=== TEST 14: A token without a jti is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-13",
                }
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
jti claim is missing



=== TEST 15: A token with a stale iat is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time() - 1200,
                    exp = ngx.time() + 120,
                    jti = "jti-test14",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-14",
                }
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



=== TEST 16: A token whose aud names another client is rejected.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "some-other-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test15",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-15",
                }
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



=== TEST 17: Transport-level failures: non-POST and missing logout_token.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"

            local res1, err = t.req_self_with_http("/bcl", "GET")
            if not res1 then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local res2
            res2, err = t.req_self_with_http("/bcl", "POST", "foo=bar")
            if not res2 then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("get: ", res1.status)
            ngx.say("post without token: ", res2.status)
        }
    }
--- response_body
get: 405
post without token: 400



=== TEST 18: Set up the Keycloak route and register the BCL URL at the client.
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



=== TEST 19: The session is rejected after the IdP delivers a back-channel logout (sid).
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



=== TEST 20: With unauth_action deny, a revoked session gets 401.
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



=== TEST 21: A sub-only logout kills the session; a later login survives.
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



=== TEST 22: With storage redis, an accepted logout token lands in redis.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

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

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    -- unique per run: the jti replay guard lives in redis,
                    -- which outlives the test nginx instances
                    jti = "jti-test21-" .. ngx.now(),
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-21",
                }
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("status: ", res.status)

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
status: 200
redis entry: true
--- error_log
OIDC backchannel logout accepted for sid sess-21



=== TEST 23: storage redis without an own redis block falls back to session.redis.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

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

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    -- unique per run: the jti replay guard lives in redis,
                    -- which outlives the test nginx instances
                    jti = "jti-test22-" .. ngx.now(),
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-22",
                }
            })

            local res, err = t.req_self_with_http("/bcl", "POST",
                                                  "logout_token=" .. token)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say("status: ", res.status)

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
status: 200
redis entry: true
--- error_log
OIDC backchannel logout accepted for sid sess-22



=== TEST 24: The endpoint answers 400 when the redis store is unreachable.
--- config
    location /t {
        content_by_lua_block {
            local t = require "lib.test_admin"
            local r_jwt = require "resty.jwt"

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

            local token = r_jwt:sign(t.read_file("t/certs/private.pem"), {
                header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
                payload = {
                    iss = "http://127.0.0.1:6724",
                    aud = "bcl-client",
                    iat = ngx.time(),
                    exp = ngx.time() + 120,
                    jti = "jti-test23",
                    events = {
                        ["http://schemas.openid.net/event/backchannel-logout"] = {}
                    },
                    sid = "sess-23",
                }
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
OIDC backchannel logout store failed



=== TEST 25: A request with the store down gets 503 and the session is kept.
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
