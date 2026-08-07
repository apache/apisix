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

our $http_config = <<'_EOC_';
    lua_shared_dict introspection 10m;
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->http_config) {
        $block->set_value("http_config", $http_config);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: introspect_session_access_token defaults to false
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local conf = {
                client_id = "course_management",
                client_secret = "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(tostring(conf.introspect_session_access_token))
        }
    }
--- response_body
false



=== TEST 2: schema rejects introspect_session_access_token when bearer_only is true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                bearer_only = true,
                introspect_session_access_token = true
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
"introspect_session_access_token" is only supported when "bearer_only" is false



=== TEST 3: Set up route with session access token introspection (default: introspect every request).
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspect_session_access_token": true,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 4: A session whose access token is still active is proxied upstream.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 200 then
                ngx.status = 500
                ngx.say("Invoking the original URI didn't return the expected result.")
                return
            end

            ngx.status = res.status
            ngx.say(true)
        }
    }
--- response_body
true



=== TEST 5: Once the identity provider ends the session, the access token is no longer accepted.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request failed: ", res and res.status or err)
                return
            end

            -- The test upstream echoes request headers, exposing the refresh
            -- token needed to end the session at the identity provider.
            local refresh_token = res.body:match("x%-refresh%-token: ([^\r\n]+)")
            if not refresh_token then
                ngx.status = 500
                ngx.say("could not read the refresh token from the upstream echo")
                return
            end

            -- End the session at Keycloak: the "logged out by other means" case.
            local logout_res
            logout_res, err = httpc:request_uri(
                "http://127.0.0.1:8080/realms/University/protocol/openid-connect/logout", {
                    method = "POST",
                    body = "client_id=course_management" ..
                           "&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5" ..
                           "&refresh_token=" .. refresh_token,
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })
            if not logout_res or logout_res.status >= 300 then
                ngx.status = 500
                ngx.say("logout at the identity provider failed: ",
                        logout_res and logout_res.status or err)
                return
            end

            res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = res.status
            local location = res.headers['Location']
            if location and location:find('/protocol/openid-connect/auth', 1, true) then
                ngx.say(true)
            end
        }
    }
--- response_body
true
--- error_code: 302
--- error_log
access token in session is no longer active



=== TEST 6: Set up route with a long introspection cache TTL.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspect_session_access_token": true,
                                "introspection_interval": 300,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 7: An active result is cached, so revocation is only picked up once the cached TTL lapses.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "student@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request failed: ", res and res.status or err)
                return
            end

            local refresh_token = res.body:match("x%-refresh%-token: ([^\r\n]+)")
            if not refresh_token then
                ngx.status = 500
                ngx.say("could not read the refresh token from the upstream echo")
                return
            end

            local logout_res
            logout_res, err = httpc:request_uri(
                "http://127.0.0.1:8080/realms/University/protocol/openid-connect/logout", {
                    method = "POST",
                    body = "client_id=course_management" ..
                           "&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5" ..
                           "&refresh_token=" .. refresh_token,
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })
            if not logout_res or logout_res.status >= 300 then
                ngx.status = 500
                ngx.say("logout at the identity provider failed: ",
                        logout_res and logout_res.status or err)
                return
            end

            -- The cached "active" from the previous request is still live, so
            -- the revoked token keeps being accepted.
            res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = res.status
            ngx.say(true)
        }
    }
--- response_body
true



=== TEST 8: Set up route whose introspection endpoint is unreachable.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:1979/introspect",
                                "introspect_session_access_token": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 9: No verdict (endpoint unreachable) fails the request but keeps the session.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 503 then
                ngx.status = 500
                ngx.say("expected 503 on the first request, got ", res.status)
                return
            end

            -- Destroying the session would send an epoch-expiry Set-Cookie.
            local set_cookie = res.headers["Set-Cookie"]
            local destroyed = false
            if set_cookie then
                local cookies = type(set_cookie) == "table" and set_cookie or {set_cookie}
                for _, c in ipairs(cookies) do
                    if c:find("Expires=Thu, 01 Jan 1970", 1, true) then
                        destroyed = true
                    end
                end
            end
            if destroyed then
                ngx.status = 500
                ngx.say("session was destroyed")
                return
            end

            -- The kept session re-checks on the next request; still dead, same 503.
            res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.say(true)
        }
    }
--- response_body
true
--- error_code: 503
--- error_log
OIDC session access token introspection failed
--- no_error_log
no longer active



=== TEST 10: Set up route with per-request session introspection (for negative-cache checks).
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspect_session_access_token": true,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 11: A replayed revoked-session cookie is answered from the negative cache.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request failed: ", res and res.status or err)
                return
            end

            local refresh_token = res.body:match("x%-refresh%-token: ([^\r\n]+)")
            if not refresh_token then
                ngx.status = 500
                ngx.say("could not read the refresh token from the upstream echo")
                return
            end

            -- End the session at Keycloak, then replay the revoked cookie twice:
            -- only the negative cache keeps the second replay off the provider.
            local logout_res
            logout_res, err = httpc:request_uri(
                "http://127.0.0.1:8080/realms/University/protocol/openid-connect/logout", {
                    method = "POST",
                    body = "client_id=course_management" ..
                           "&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5" ..
                           "&refresh_token=" .. refresh_token,
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })
            if not logout_res or logout_res.status >= 300 then
                ngx.status = 500
                ngx.say("logout at the identity provider failed: ",
                        logout_res and logout_res.status or err)
                return
            end

            -- first replay: fresh introspection reports inactive
            res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            if res.status ~= 302 then
                ngx.status = 500
                ngx.say("expected 302 on the first replay, got ", res.status)
                return
            end

            -- second replay: answered from the negative cache
            res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.say(true)
        }
    }
--- response_body
true
--- error_code: 302
--- error_log
the identity provider reports the token as inactive
cached introspection result reports the token as inactive



=== TEST 12: Set up a login route and a deny route for /hello (for unauth_action=deny checks).
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspect_session_access_token": true,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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

            local code2, body2 = t('/apisix/admin/routes/2',
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspect_session_access_token": true,
                                "set_refresh_token_header": true,
                                "unauth_action": "deny",
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
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

            if code2 >= 300 then
                ngx.status = code2
            end
            ngx.say(body2)
        }
    }
--- response_body
passed
passed



=== TEST 13: unauth_action=deny returns 401, not 302, once the session's access token is inactive.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request failed: ", res and res.status or err)
                return
            end

            local refresh_token = res.body:match("x%-refresh%-token: ([^\r\n]+)")
            if not refresh_token then
                ngx.status = 500
                ngx.say("could not read the refresh token from the upstream echo")
                return
            end

            -- End the session at Keycloak, then hit /hello (unauth_action:
            -- deny) with the same cookie: inactive token, deny means 401.
            local logout_res
            logout_res, err = httpc:request_uri(
                "http://127.0.0.1:8080/realms/University/protocol/openid-connect/logout", {
                    method = "POST",
                    body = "client_id=course_management" ..
                           "&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5" ..
                           "&refresh_token=" .. refresh_token,
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })
            if not logout_res or logout_res.status >= 300 then
                ngx.status = 500
                ngx.say("logout at the identity provider failed: ",
                        logout_res and logout_res.status or err)
                return
            end

            local hello_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            res, err = httpc:request_uri(hello_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = res.status
            ngx.say(true)
        }
    }
--- response_body
true
--- error_code: 401
--- error_log
access token in session is no longer active
