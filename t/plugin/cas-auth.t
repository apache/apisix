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



=== TEST 8: schema rejects samesite=None with secure=false
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
                    samesite = "None",
                    secure = false,
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like
.*cookie.secure must be true when cookie.samesite is "None".*



=== TEST 9: is_safe_redirect rejects external and protocol-relative URLs
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



=== TEST 10: sign and verify roundtrip + tamper detection
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



=== TEST 11: callback_path derives path from relative and absolute cas_callback_uri
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers
            local cases = {
                {"/cas_callback",                          "/cas_callback"},
                {"https://app.example.com/cas_callback",   "/cas_callback"},
                {"http://app.example.com:8443/cb",         "/cb"},
                {"https://app.example.com",                "/"},
                {"https://app.example.com/cb?from=cas",    "/cb"},
                {"https://app.example.com/cb#frag",        "/cb"},
            }
            for _, c in ipairs(cases) do
                local got = h.callback_path(c[1])
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



=== TEST 12: add route with an absolute cas_callback_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas-abs',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "plugins": {
                            "cas-auth": {
                                "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/cas",
                                "cas_callback_uri": "https://app.example.com/cas_callback",
                                "logout_uri": "/logout",
                                "cookie": {
                                    "secret": "0123456789abcdef0123456789abcdef"
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



=== TEST 13: absolute cas_callback_uri keeps service URL fixed despite forged Host
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"

            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Host"] = "attacker.example.net",
                }
            })
            if not res then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            ngx.say(res.status)
            ngx.say(res.headers['Location'])
        }
    }
--- response_body_like
^302
.*service=https%3A%2F%2Fapp\.example\.com%2Fcas_callback.*$



=== TEST 14: add route for callback initiation-cookie gate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas-gate',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host": "127.0.0.3",
                        "plugins": {
                            "cas-auth": {
                                "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/cas",
                                "cas_callback_uri": "/cas_callback",
                                "logout_uri": "/logout",
                                "cookie": {
                                    "secret": "0123456789abcdef0123456789abcdef",
                                    "secure": false
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



=== TEST 15: callback without initiation cookie returns 401 and creates no session
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                .. "/cas_callback?ticket=ST-test"

            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.3",
                }
            })
            if not res then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end

            ngx.say(res.status)

            local set_cookie = res.headers['Set-Cookie']
            local has_session = false
            if type(set_cookie) == "string" then
                if set_cookie:find("^CAS_SESSION_") then
                    has_session = true
                end
            elseif type(set_cookie) == "table" then
                for _, c in ipairs(set_cookie) do
                    if c:find("^CAS_SESSION_") then
                        has_session = true
                        break
                    end
                end
            end
            ngx.say("session_cookie_set=", tostring(has_session))
        }
    }
--- response_body
401
session_cookie_set=false



=== TEST 16: callback with invalid initiation cookie returns 401 and creates no session
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                .. "/cas_callback?ticket=ST-test"

            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.3",
                    ["Cookie"] = "CAS_REQUEST_URI=not-a-valid-signed-value",
                }
            })
            if not res then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end

            ngx.say(res.status)

            local set_cookie = res.headers['Set-Cookie']
            local has_session = false
            if type(set_cookie) == "string" then
                if set_cookie:find("^CAS_SESSION_") then
                    has_session = true
                end
            elseif type(set_cookie) == "table" then
                for _, c in ipairs(set_cookie) do
                    if c:find("^CAS_SESSION_") then
                        has_session = true
                        break
                    end
                end
            end
            ngx.say("session_cookie_set=", tostring(has_session))
        }
    }
--- response_body
401
session_cookie_set=false



=== TEST 17: session_opts derives distinct cookie names and fingerprints per CAS configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers

            local a = h.session_opts({
                idp_uri = "http://cas-a.example/cas",
                cas_callback_uri = "/cb",
            })
            local b = h.session_opts({
                idp_uri = "http://cas-b.example/cas",
                cas_callback_uri = "/cb",
            })
            local c = h.session_opts({
                idp_uri = "http://cas-a.example/cas",
                cas_callback_uri = "/other-cb",
            })
            local a2 = h.session_opts({
                idp_uri = "http://cas-a.example/cas",
                cas_callback_uri = "/cb",
            })

            assert(a.cookie_name ~= b.cookie_name, "different idp_uri must produce different cookie_name")
            assert(a.cookie_name ~= c.cookie_name, "different cas_callback_uri must produce different cookie_name")
            assert(a.fingerprint ~= b.fingerprint, "different idp_uri must produce different fingerprint")
            assert(a.fingerprint ~= c.fingerprint, "different cas_callback_uri must produce different fingerprint")
            assert(a.cookie_name == a2.cookie_name, "same conf must produce same cookie_name")
            assert(a.fingerprint == a2.fingerprint, "same conf must produce same fingerprint")
            assert(a.cookie_name:find("^CAS_SESSION_"), "cookie_name must start with CAS_SESSION_")
            assert(#a.fingerprint == 64, "fingerprint must be 64 hex chars (sha256)")
            assert(a.fingerprint:find("^[0-9a-f]+$"), "fingerprint must be lower-case hex")

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: pack_entry and unpack_entry roundtrip and reject legacy entries
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers

            local fp = "abcd1234"
            local user = "alice@example.com"
            local entry = h.pack_entry(fp, user)
            local got_fp, got_user = h.unpack_entry(entry)
            assert(got_fp == fp, "fingerprint did not round-trip")
            assert(got_user == user, "user did not round-trip")

            -- Legacy entries (pre-fingerprint, no separator) must be rejected.
            local nil_fp, nil_user = h.unpack_entry("legacy-user-no-pipe")
            assert(nil_fp == nil, "legacy entry should produce nil fingerprint")
            assert(nil_user == nil, "legacy entry should produce nil user")

            local nfp, nu = h.unpack_entry(nil)
            assert(nfp == nil and nu == nil, "nil entry must return nil,nil")

            -- Split on first separator so a username containing the separator
            -- is preserved verbatim.
            local fp2, user2 = h.unpack_entry(h.pack_entry("xx", "ali|ce"))
            assert(fp2 == "xx", "fingerprint split mismatch")
            assert(user2 == "ali|ce", "user split mismatch")

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 19: add routes with distinct CAS configurations for the scoping test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")

            local function put_route(id, conf, uri_path)
                local payload = {
                    methods = {"GET"},
                    host = "127.0.0.4",
                    uri = uri_path,
                    plugins = { ["cas-auth"] = conf },
                    upstream = { nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin" },
                }
                local code, body = t('/apisix/admin/routes/' .. id,
                    ngx.HTTP_PUT, core.json.encode(payload))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return false
                end
                return true
            end

            local conf_a = {
                idp_uri = "http://127.0.0.1:9999/cas-a",
                cas_callback_uri = "/cb-a",
                logout_uri = "/logout",
                cookie = { secret = "0123456789abcdef0123456789abcdef", secure = false },
            }
            local conf_b = {
                idp_uri = "http://127.0.0.1:9999/cas-b",
                cas_callback_uri = "/cb-b",
                logout_uri = "/logout",
                cookie = { secret = "0123456789abcdef0123456789abcdef", secure = false },
            }

            -- /hello and /uri are existing actions in t/lib/server.lua;
            -- the upstream returns 200 for both.
            if not put_route("cas-scope-a", conf_a, "/hello") then return end
            if not put_route("cas-scope-b", conf_b, "/uri") then return end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: sessions from one CAS configuration are not honoured under another
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local h = plugin._test_helpers
            local http = require("resty.http")

            local conf_a = {
                idp_uri = "http://127.0.0.1:9999/cas-a",
                cas_callback_uri = "/cb-a",
            }
            local conf_b = {
                idp_uri = "http://127.0.0.1:9999/cas-b",
                cas_callback_uri = "/cb-b",
            }
            local opts_a = h.session_opts(conf_a)
            local opts_b = h.session_opts(conf_b)
            assert(opts_a.cookie_name ~= opts_b.cookie_name,
                "routes with different CAS configs must use different cookie names")

            -- Plant a session entry for Route A's fingerprint, keyed by a synthetic ticket.
            local ticket = "ST-scope-test-" .. tostring(ngx.now())
            ngx.shared.cas_sessions:set(ticket, h.pack_entry(opts_a.fingerprint, "alice"), 60)

            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            -- (1) Route A honours its own session, upstream /hello returns 200.
            local res_a = httpc:request_uri(base .. "/hello", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.4",
                    ["Cookie"] = opts_a.cookie_name .. "=" .. ticket,
                }
            })
            assert(res_a, "route A request failed")
            assert(res_a.status == 200,
                "route A should honour its own session, got status " .. res_a.status)

            -- (2) Route B receives Route A's cookie name; B looks for its own
            -- cookie name and finds nothing -> redirect to its own IdP.
            local res_b1 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.4",
                    ["Cookie"] = opts_a.cookie_name .. "=" .. ticket,
                }
            })
            assert(res_b1, "route B request failed")
            assert(res_b1.status == 302,
                "route B must not honour route A's cookie name, got status " .. res_b1.status)

            -- (3) Route B receives a forged cookie under B's name but pointing
            -- at Route A's stored session. The fingerprint check rejects it.
            local res_b2 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.4",
                    ["Cookie"] = opts_b.cookie_name .. "=" .. ticket,
                }
            })
            assert(res_b2, "route B forged-cookie request failed")
            assert(res_b2.status == 302,
                "route B must reject a foreign session payload, got status " .. res_b2.status)

            ngx.shared.cas_sessions:delete(ticket)
            ngx.say("passed")
        }
    }
--- response_body
passed
