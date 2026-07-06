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

            -- No shared-dict entry should have been written for ST-test
            -- under any configuration's fingerprint namespace.
            local in_store = false
            for _, k in ipairs(ngx.shared.cas_sessions:get_keys(0)) do
                if k:find(":ST-test", 1, true) then
                    in_store = true
                    break
                end
            end
            ngx.say("session_in_store=", tostring(in_store))
        }
    }
--- response_body
401
session_cookie_set=false
session_in_store=false



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

            -- No shared-dict entry should have been written for ST-test
            -- under any configuration's fingerprint namespace.
            local in_store = false
            for _, k in ipairs(ngx.shared.cas_sessions:get_keys(0)) do
                if k:find(":ST-test", 1, true) then
                    in_store = true
                    break
                end
            end
            ngx.say("session_in_store=", tostring(in_store))
        }
    }
--- response_body
401
session_cookie_set=false
session_in_store=false



=== TEST 17: Add dedicated routes for the per-config scoping test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Use priority=10 so these routes win over the no-host catch-all
            -- registered in earlier tests (cas-abs), and unique hosts so they
            -- don't collide with cas1/cas2.
            local function put(id, host, cb)
                local code, body = t('/apisix/admin/routes/' .. id,
                     ngx.HTTP_PUT,
                     string.format([[{
                            "methods": ["GET", "POST"],
                            "host": %q,
                            "priority": 10,
                            "plugins": {
                                "cas-auth": {
                                    "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/cas",
                                    "cas_callback_uri": %q,
                                    "logout_uri": "/logout",
                                    "cookie": {
                                        "secret": "0123456789abcdef0123456789abcdef",
                                        "secure": false
                                    }
                                }
                            },
                            "upstream": {
                                "nodes": {"127.0.0.1:1980": 1},
                                "type": "roundrobin"
                            },
                            "uri": "/*"
                    }]], host, cb))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return false
                end
                return true
            end

            if not put("cas-scope-a", "127.0.0.10", "/cas_callback") then return end
            if not put("cas-scope-b", "127.0.0.11", "/cas_callback_alt") then return end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: sessions from one CAS configuration are not honoured under another
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local resty_sha256 = require("resty.sha256")
            local str = require("resty.string")

            -- Recompute the per-config fingerprint here rather than exposing
            -- the plugin's session_opts helper. Algorithm matches the plugin.
            local function fingerprint(idp, cb)
                local s = resty_sha256:new()
                s:update(idp .. "|" .. cb)
                return str.to_hex(s:final())
            end

            local idp = "http://127.0.0.1:8080/realms/test/protocol/cas"
            local fp_a = fingerprint(idp, "/cas_callback")
            local fp_b = fingerprint(idp, "/cas_callback_alt")
            assert(fp_a ~= fp_b, "two configs must yield different fingerprints")

            -- Plant a session as the plugin would: store key namespaced by the
            -- fingerprint, value of "<fp>|<user>". This exercises the plugin's
            -- session-read path (with_session_id -> store:get -> unpack_entry
            -- -> fingerprint check) on scope-a.
            local ticket = "ST-scope-test-" .. tostring(ngx.now())
            local key_a = fp_a .. ":" .. ticket
            local ok, err = ngx.shared.cas_sessions:set(key_a, fp_a .. "|alice", 60)
            assert(ok, "plant failed: " .. tostring(err))

            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            -- Route scope-a (host 127.0.0.10) honours its own session.
            local res, err2 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.10",
                    ["Cookie"] = "CAS_SESSION_" .. fp_a .. "=" .. ticket,
                },
            })
            assert(res, "scope-a request failed: " .. tostring(err2))
            assert(res.status == 200,
                "scope-a should honour its own session, got status " .. res.status)

            -- Same cookie sent to scope-b (different cas_callback_uri, different
            -- fingerprint): scope-b looks for CAS_SESSION_<fp_b>, doesn't find
            -- it, redirects to its own IdP.
            res, err2 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.11",
                    ["Cookie"] = "CAS_SESSION_" .. fp_a .. "=" .. ticket,
                },
            })
            assert(res, "scope-b request failed: " .. tostring(err2))
            assert(res.status == 302,
                "scope-b must not honour foreign cookie name, got "
                .. res.status)

            -- A forged cookie under scope-b's own name pointing at scope-a's
            -- ticket: the namespaced store key under fp_b doesn't exist,
            -- so the request still falls through to first_access.
            res, err2 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.11",
                    ["Cookie"] = "CAS_SESSION_" .. fp_b .. "=" .. ticket,
                },
            })
            assert(res, "scope-b forged-cookie request failed: " .. tostring(err2))
            assert(res.status == 302,
                "scope-b must not honour foreign session payload, got "
                .. res.status)

            -- Plant an entry under scope-b's namespaced key but with scope-a's
            -- fingerprint inside the stored value. This is the only path that
            -- reaches the in-value fingerprint check in with_session_id:
            -- store:get finds the entry, but unpack_entry returns fp_a while
            -- the route's opts.fingerprint is fp_b -> first_access (302).
            local key_b_forged = fp_b .. ":" .. ticket
            local ok2, err3 = ngx.shared.cas_sessions:set(key_b_forged,
                fp_a .. "|alice", 60)
            assert(ok2, "forged plant failed: " .. tostring(err3))

            res, err2 = httpc:request_uri(base .. "/uri", {
                method = "GET",
                headers = {
                    ["Host"] = "127.0.0.11",
                    ["Cookie"] = "CAS_SESSION_" .. fp_b .. "=" .. ticket,
                },
            })
            assert(res, "scope-b fingerprint-mismatch request failed: " .. tostring(err2))
            assert(res.status == 302,
                "scope-b must reject a stored entry whose fingerprint does not match, got "
                .. res.status)

            ngx.shared.cas_sessions:delete(key_a)
            ngx.shared.cas_sessions:delete(key_b_forged)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 19: add route for empty-body SLO callback test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas-slo',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host": "127.0.0.20",
                        "priority": 10,
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
                            "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 20: malformed SLO POST to callback returns 400, not 500
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            -- (1) no body at all: get_body() returns nil, which must not be
            -- indexed (500) but fall through to a clean 400.
            local res, err = httpc:request_uri(base .. "/cas_callback", {
                method = "POST",
                headers = { ["Host"] = "127.0.0.20" },
            })
            assert(res, "request failed: " .. tostring(err))
            assert(res.status == 400,
                "expected 400 for empty-body SLO POST, got " .. res.status)
            assert(res.body and res.body:find("no ticket", 1, true),
                "expected 'no ticket' message, got: " .. tostring(res.body))

            -- (2) body present but SessionIndex empty: still a malformed
            -- logout, must be 400 rather than passing an empty ticket through.
            res, err = httpc:request_uri(base .. "/cas_callback", {
                method = "POST",
                headers = { ["Host"] = "127.0.0.20" },
                body = "<samlp:SessionIndex></samlp:SessionIndex>",
            })
            assert(res, "request failed: " .. tostring(err))
            assert(res.status == 400,
                "expected 400 for empty SessionIndex, got " .. res.status)

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 21: add route whose upstream is a closed port for the SLO fall-through test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas-slo-noproxy',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host": "127.0.0.21",
                        "priority": 10,
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
                            "nodes": {"127.0.0.1:1": 1},
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



=== TEST 22: well-formed SLO POST stops at the plugin and is never proxied upstream
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            -- A POST carrying a valid SessionIndex must be terminated by the
            -- plugin (200), not fall through to the upstream. The upstream is a
            -- closed port, so any fall-through would surface as a 502.
            local res, err = httpc:request_uri(base .. "/cas_callback", {
                method = "POST",
                headers = { ["Host"] = "127.0.0.21" },
                body = "<samlp:SessionIndex>ST-no-such-session</samlp:SessionIndex>",
            })
            assert(res, "request failed: " .. tostring(err))
            assert(res.status == 200,
                "expected 200 from plugin, got " .. res.status ..
                " (non-200 means the SLO POST was proxied upstream)")

            ngx.say("passed")
        }
    }
--- response_body
passed
