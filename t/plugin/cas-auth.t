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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: Add route for sp1
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_cas")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host" : "127.0.0.1",
                        "plugins": {
                            "cas-auth": ]] .. core.json.encode(opts) .. [[
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



=== TEST 2: login and logout ok
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_cas"

            local path = "/uri"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, cas_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie
                }
            })
            assert(res.status == 200)
            ngx.say(res.body)

            res, err = kc.logout_keycloak(uri .. "/logout", cas_cookie, keycloak_cookie)
            assert(res.status == 200)
        }
    }
--- response_body_like
uri: /uri
cookie: .*
host: 127.0.0.1:1984
user-agent: .*
x-real-ip: 127.0.0.1



=== TEST 3: Add route for sp2
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_cas")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas2',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host" : "127.0.0.2",
                        "plugins": {
                            "cas-auth": ]] .. core.json.encode(opts) .. [[
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



=== TEST 4: login sp1 and sp2, then do single logout
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_cas"

            local path = "/uri"

            -- login to sp1
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, cas_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie
                }
            })
            assert(res.status == 200)

            -- login to sp2, which would skip login at keycloak side
            local uri2 = "http://127.0.0.2:" .. ngx.var.server_port

            local res, err, cas_cookie2 = kc.login_keycloak_for_second_sp(uri2 .. path, keycloak_cookie)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri2 .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie2
                }
            })
            assert(res.status == 200)

            -- SLO (single logout)
            res, err = kc.logout_keycloak(uri .. "/logout", cas_cookie, keycloak_cookie)
            assert(res.status == 200)

            -- login to sp2, which would do normal login process at keycloak side
            local res, err, cas_cookie2, keycloak_cookie = kc.login_keycloak(uri2 .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie2
                }
            })
            assert(res.status == 200)

            -- logout sp2
            res, err = kc.logout_keycloak(uri2 .. "/logout", cas_cookie2, keycloak_cookie)
            assert(res.status == 200)
        }
    }



=== TEST 5: schema rejects missing cookie.secret
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "http://127.0.0.1:8080",
                cas_callback_uri = "/cas_callback",
                logout_uri = "/logout",
                cookie = {},
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like
.*property "secret" is required.*



=== TEST 6: schema rejects cookie.secret shorter than 32 chars
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "http://127.0.0.1:8080",
                cas_callback_uri = "/cas_callback",
                logout_uri = "/logout",
                cookie = { secret = "tooshort" },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like
.*string too short.*



=== TEST 7: schema rejects cookie.samesite=Strict
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "http://127.0.0.1:8080",
                cas_callback_uri = "/cas_callback",
                logout_uri = "/logout",
                cookie = {
                    secret = "0123456789abcdef0123456789abcdef",
                    samesite = "Strict",
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like
.*samesite.*



=== TEST 8: is_safe_redirect rejects external and protocol-relative URLs
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers
            local cases = {
                {"/foo",                 true},
                {"/foo?bar=baz",         true},
                {"https://evil.com/x",   false},
                {"//evil.com/x",         false},
                {"\\\\evil.com",         false},
                {"/foo\r\nLocation: x", false},
                {"",                     false},
                {nil,                    false},
            }
            for _, c in ipairs(cases) do
                local got = h.is_safe_redirect(c[1])
                if got ~= c[2] then
                    ngx.say("FAIL ", tostring(c[1]), " expected ", tostring(c[2]),
                            " got ", tostring(got))
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 9: sign and verify roundtrip + tamper detection
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers
            local secret = "0123456789abcdef0123456789abcdef"
            local signed = h.sign_value(secret, "/foo?bar=baz")
            assert(signed, "sign_value returned nil")

            local got = h.verify_value(secret, signed)
            if got ~= "/foo?bar=baz" then
                ngx.say("FAIL roundtrip got=", tostring(got))
                return
            end

            -- flip last char of the signature segment
            local tampered = signed:sub(1, -2) ..
                (signed:sub(-1) == "A" and "B" or "A")
            if h.verify_value(secret, tampered) ~= nil then
                ngx.say("FAIL tampered signature accepted")
                return
            end

            -- a different secret must not validate
            if h.verify_value("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", signed) ~= nil then
                ngx.say("FAIL wrong secret accepted")
                return
            end

            -- nil and malformed inputs
            if h.verify_value(secret, nil) ~= nil
                or h.verify_value(secret, "no-dot-here") ~= nil
                or h.verify_value(secret, "abc.def") ~= nil then
                ngx.say("FAIL malformed cookie accepted")
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed
