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
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();


__DATA__

=== TEST 1: minimal valid conf (ldap_uri + base_dn) passes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 2: missing ldap_uri is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                base_dn = "ou=users,dc=example,dc=org",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/property "ldap_uri" is required/



=== TEST 3: missing base_dn is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/property "base_dn" is required/



=== TEST 4: use_ldaps and use_starttls are mutually exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                use_ldaps = true,
                use_starttls = true,
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
use_ldaps and use_starttls are mutually exclusive



=== TEST 5: use_ldaps alone (port-less uri) passes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "ldap.example.org",
                base_dn = "ou=users,dc=example,dc=org",
                use_ldaps = true,
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 6: bind_dn set without ldap_password is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                bind_dn = "cn=admin,dc=example,dc=org",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
ldap_password is required when bind_dn is set



=== TEST 7: bind_dn with ldap_password passes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                bind_dn = "cn=admin,dc=example,dc=org",
                ldap_password = "adminpassword",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 8: attribute with a bad pattern is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                attribute = "1abc",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 9: attribute containing a space is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                attribute = "a b",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 10: valid attribute (uid) passes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                attribute = "uid",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 11: size_limit below the floor of 2 is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                size_limit = 1,
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 12: set up a route protected by ldap-auth-advanced (live LDAP)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: no credential header -> 401 with WWW-Authenticate ldap realm
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: ldap realm="ldap"



=== TEST 14: malformed base64 payload ("aca_a" does not decode) -> 401
--- request
GET /hello
--- more_headers
Authorization: ldap aca_a
--- error_code: 401



=== TEST 15: base64 payload without a ':' separator (decodes to "useronly") -> 401
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcm9ubHk=
--- error_code: 401



=== TEST 16: empty password (payload decodes to "user01:") rejected before any bind (RFC 4513 5.1.2 unauthenticated bind)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 17: scheme word parsed case-insensitively (uppercase), empty password still rejected (creds: user01:)
--- request
GET /hello
--- more_headers
Authorization: LDAP dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 18: scheme word parsed case-insensitively (mixed case), empty password still rejected (creds: user01:)
--- request
GET /hello
--- more_headers
Authorization: lDaP dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 19: set up a route with header_type basic
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "header_type": "basic"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: header_type basic emits a Basic-scheme WWW-Authenticate
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: Basic realm="ldap"



=== TEST 21: inbound identity headers are cleared before any auth work, on every path
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local headers = {
                "X-Authenticated-Groups", "X-Consumer-Username",
                "X-Credential-Identifier", "X-Consumer-Custom-ID",
                "X-Authenticated-User-Dn", "X-Authenticated-Username",
            }
            local ctx = { var = {} }
            local before = {}
            for i, h in ipairs(headers) do
                before[i] = core.request.header(ctx, h) or "nil"
            end
            -- no credential header -> auth_failed path; the strip must still happen
            plugin.rewrite({ header_type = "ldap", realm = "ldap" }, ctx)
            local after = {}
            for i, h in ipairs(headers) do
                after[i] = core.request.header(ctx, h) or "nil"
            end
            ngx.say("before: ", table.concat(before, " "))
            ngx.say("after: ", table.concat(after, " "))
        }
    }
--- more_headers
X-Authenticated-Groups: injected
X-Consumer-Username: spoofed-user
X-Credential-Identifier: spoofed-cred
X-Consumer-Custom-ID: spoofed-id
X-Authenticated-User-Dn: spoofed-dn
X-Authenticated-Username: spoofed-login
--- response_body
before: injected spoofed-user spoofed-cred spoofed-id spoofed-dn spoofed-login
after: nil nil nil nil nil nil



=== TEST 22: set up a route with multi-auth wrapping ldap-auth-advanced and basic-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "ldap-auth-advanced": {
                                        "ldap_uri": "127.0.0.1:1389",
                                        "base_dn": "ou=users,dc=example,dc=org",
                                        "attribute": "uid"
                                    }
                                },
                                {
                                    "basic-auth": {}
                                }
                            ]
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: under multi-auth ldap-auth-advanced declines quietly (creds: user01:)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOg==
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}
--- response_headers
WWW-Authenticate: Basic realm="basic"
--- no_error_log
empty password



=== TEST 24: set up the plain search-then-bind route (uid attribute)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "keepalive_pool_size": 4
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: wrong password -> 401 (a result-code failure, not a transport error) (creds: user01:wrong)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOndyb25n
--- error_code: 401



=== TEST 26: unknown user -> 401 (the user search returns 0 entries) (creds: nouser:x)
--- request
GET /hello
--- more_headers
Authorization: ldap bm91c2VyOng=
--- error_code: 401



=== TEST 27: ambiguous match (two uid=dupuser entries) -> 401 + "ambiguous" warn (creds: dupuser:duppass1)
--- request
GET /hello
--- more_headers
Authorization: ldap ZHVwdXNlcjpkdXBwYXNzMQ==
--- error_code: 401
--- grep_error_log eval
qr/ambiguous user match/
--- grep_error_log_out
ambiguous user match



=== TEST 28: point the route at a dead LDAP port (transport-error case)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1390",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "timeout": 1000
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 29: LDAP unreachable -> 500 (a transport error is never an auth failure) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP connect failed



=== TEST 30: set up an LDAPS route on 1636 (use_ldaps, ssl_verify off)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1636",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "use_ldaps": true,
                            "ssl_verify": false
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 31: happy path over LDAPS (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 32: set up a StartTLS route on 1389 (use_starttls, ssl_verify off)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "use_starttls": true,
                            "ssl_verify": false
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 33: happy path over StartTLS (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 34: restore the plain search-then-bind route for the injection suite
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 35: filter-injection usernames each 401 (none widens the search)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local port = ngx.var.server_port
            -- RFC 4515 s3 specials plus a NUL byte. Once escaped, every payload
            -- is a literal that matches NO user, so each 401s via the "user not
            -- found" path. The log assertions below are the real proof of
            -- escaping: an UNescaped "*" would build the presence filter (uid=*),
            -- match >1 entry, and 401 via the "ambiguous user match" path instead
            -- -- so we assert "user not found" IS logged and "ambiguous user
            -- match" is NOT (status 401 alone cannot tell the two paths apart).
            local injections = { "*", "*)(objectClass=*", "(", ")", "\\", "\0" }
            local all_401 = true
            local statuses = {}
            for _, u in ipairs(injections) do
                local hc = http.new()
                local cred = ngx.encode_base64(u .. ":x")
                local res, err = hc:request_uri(
                    "http://127.0.0.1:" .. port .. "/hello",
                    { headers = { ["Authorization"] = "ldap " .. cred } })
                local st = res and res.status or ("ERR:" .. tostring(err))
                statuses[#statuses + 1] = tostring(st)
                if st ~= 401 then all_401 = false end
            end
            ngx.say("all_401: ", tostring(all_401))
            ngx.say("statuses: ", table.concat(statuses, ","))
        }
    }
--- response_body
all_401: true
statuses: 401,401,401,401,401,401
--- error_log
user not found
--- no_error_log
ambiguous user match



=== TEST 36: username with an invalid UTF-8 byte -> clean 401, never a 500
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local port = ngx.var.server_port
            -- 0xFF is a lone high byte: never valid UTF-8. filter.escape leaves it
            -- untouched, so if it reached the search the library's filter grammar would
            -- reject it as a "syntax error", which the plugin's non-result-code
            -- branch turns into HTTP 500. A malformed username is a bad credential
            -- (a client error), so it must be rejected up front as a clean 401 --
            -- never surfaced as a server-side 500.
            local hc = http.new()
            local cred = ngx.encode_base64(string.char(0xff) .. ":x")
            local res, err = hc:request_uri(
                "http://127.0.0.1:" .. port .. "/hello",
                { headers = { ["Authorization"] = "ldap " .. cred } })
            ngx.say("status: ", res and res.status or ("ERR:" .. tostring(err)))
        }
    }
--- response_body
status: 401
--- error_log
invalid username
--- no_error_log
LDAP user search failed



=== TEST 37: well-formed multibyte UTF-8 username reaches the search and 401s as not-found
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local port = ngx.var.server_port
            -- "h" + U+00E9 (e-acute, bytes 0xC3 0xA9) + "llo": valid 2-byte UTF-8.
            -- It must pass the encoding check and reach the search, where it
            -- matches no user -> the "user not found" 401 path. This proves valid
            -- multibyte input is NOT rejected as bad encoding (only invalid byte
            -- sequences are).
            local hc = http.new()
            local username = "h" .. string.char(0xc3, 0xa9) .. "llo"
            local cred = ngx.encode_base64(username .. ":x")
            local res, err = hc:request_uri(
                "http://127.0.0.1:" .. port .. "/hello",
                { headers = { ["Authorization"] = "ldap " .. cred } })
            ngx.say("status: ", res and res.status or ("ERR:" .. tostring(err)))
        }
    }
--- response_body
status: 401
--- error_log
user not found
--- no_error_log
invalid username



=== TEST 38: username with a trailing '~' reaches the search and 401s as not-found
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local port = ngx.var.server_port
            -- RFC 4515 UTF1SUBSET (%x5D-7F) includes '~' (0x7e), so "admin~" is a
            -- legal assertion value and a legal directory username. The filter
            -- grammar only tolerates a raw '~' mid-value, so filter.escape emits
            -- it as "\7e"; the compiler un-escapes that back to '~' and the search
            -- goes out with the exact username. It must therefore reach the search
            -- and take the "user not found" 401 path -- never be turned away by the
            -- compile pre-check, which is reserved for input the grammar genuinely
            -- cannot express (e.g. invalid UTF-8, TEST 44).
            local hc = http.new()
            local cred = ngx.encode_base64("admin~:x")
            local res, err = hc:request_uri(
                "http://127.0.0.1:" .. port .. "/hello",
                { headers = { ["Authorization"] = "ldap " .. cred } })
            ngx.say("status: ", res and res.status or ("ERR:" .. tostring(err)))
        }
    }
--- response_body
status: 401
--- error_log
user not found
--- no_error_log
invalid username



=== TEST 39: set up the three concurrent-probe routes (churn + anon-secret + svc-secret)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- route 1 (/hello): bind_dn UNSET, the pool-churn route.
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "keepalive_pool_size": 4
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/hello"
            }]])
            -- route 2 (/uri): bind_dn UNSET -- searches anonymously (Route A).
            local code2 = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "keepalive_pool_size": 4
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            -- route 3 (/hello1): bind_dn SET -- searches as the service account (Route B).
            local code3 = t('/apisix/admin/routes/3', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "keepalive_pool_size": 4
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/hello1"
            }]])
            local ok = code < 300 and code2 < 300 and code3 < 300
            ngx.say(ok and "passed" or "failed")
        }
    }
--- response_body
passed



=== TEST 40: CONCURRENT bind-state-leak probe: anon re-bind must not leak
--- config
    location /probe {
        content_by_lua_block {
            local http = require("resty.http")
            local args = ngx.req.get_uri_args()
            local hc = http.new()
            local cred = ngx.encode_base64(args.u .. ":" .. args.p)
            local res, err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. args.path,
                { headers = { ["Authorization"] = "ldap " .. cred } })
            ngx.print(res and tostring(res.status) or ("ERR:" .. tostring(err)))
        }
    }
    location /t {
        content_by_lua_block {
            -- Phase 1: CONCURRENTLY authenticate several end users on the
            -- bind_dn-UNSET churn route so multiple pooled sockets end up
            -- bound as DIFFERENT end users.
            -- keepalive_pool_size=4 (>1) and all routes share pool 127.0.0.1:1389.
            local churn = {
                {u="user01", p="password1"}, {u="user02", p="password2"},
                {u="jdoe",   p="janesecret"},
            }
            local reqs = {}
            for i = 1, 9 do
                local c = churn[((i - 1) % 3) + 1]
                reqs[i] = { "/probe", { args = { path = "/hello", u = c.u, p = c.p } } }
            end
            -- ngx.thread.spawn drives the concurrent capture_multi wave.
            local th = assert(ngx.thread.spawn(function()
                return { ngx.location.capture_multi(reqs) }
            end))
            local _, churn_resps = ngx.thread.wait(th)
            local churn_all_200 = true
            for _, r in ipairs(churn_resps) do
                if r.body ~= "200" then churn_all_200 = false end
            end

            -- Phase 2: Route A (bind_dn UNSET) authenticating `secretuser`, which
            -- is hidden from an anonymous search. Its anonymous simple_bind("","")
            -- MUST reset any reused (end-user-bound) socket to anonymous -> the
            -- search finds nothing -> 401. A leaked end-user bind would resolve
            -- secretuser and 200.
            local a = {}
            for i = 1, 5 do
                a[i] = { "/probe", { args = { path = "/uri", u = "secretuser", p = "secretpass" } } }
            end
            local ares = { ngx.location.capture_multi(a) }
            local routeA_all_401 = true
            for _, r in ipairs(ares) do
                if r.body ~= "401" then routeA_all_401 = false end
            end

            -- Phase 3: Route B (bind_dn SET) authenticating `secretuser`. Its
            -- search bind as the service account resolves secretuser -> 200.
            local b = {}
            for i = 1, 5 do
                b[i] = { "/probe", { args = { path = "/hello1", u = "secretuser", p = "secretpass" } } }
            end
            local bres = { ngx.location.capture_multi(b) }
            local routeB_all_200 = true
            for _, r in ipairs(bres) do
                if r.body ~= "200" then routeB_all_200 = false end
            end

            ngx.say("churn_all_200: ", tostring(churn_all_200))
            ngx.say("routeA_anon_all_401: ", tostring(routeA_all_401))
            ngx.say("routeB_svc_all_200: ", tostring(routeB_all_200))
        }
    }
--- timeout: 15
--- response_body
churn_all_200: true
routeA_anon_all_401: true
routeB_svc_all_200: true



=== TEST 41: set up the /uri header-printing route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "set_user_dn_header": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/uri"
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



=== TEST 42: spoofed identity headers never reach the upstream (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
X-Consumer-Username: spoofed-user
X-Credential-Identifier: spoofed-cred
X-Consumer-Custom-ID: spoofed-id
X-Authenticated-Groups: spoofed-groups
X-Authenticated-User-Dn: spoofed-dn
X-Authenticated-Username: spoofed-login
--- error_code: 200
--- response_body_like eval
qr/uri: \/uri\nauthorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==\nhost: localhost\nx-authenticated-groups: (Domain Admins,developers|developers,Domain Admins)\nx-authenticated-user-dn: cn=user01,ou=users,dc=example,dc=org\nx-authenticated-username: user01\nx-real-ip: 127\.0\.0\.1\n/
--- response_body_unlike eval
qr/spoofed/



=== TEST 43: RFC 4512 attribute forms are accepted (descriptor, OID, options)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local cases = {
                "sAMAccountName",
                "cn;lang-en",
                "1.2.840.113556.1.4.656",
                "0.9.2342.19200300.100.1.1;binary",
            }
            for _, attr in ipairs(cases) do
                local ok = plugin.check_schema({
                    ldap_uri = "127.0.0.1:1389",
                    base_dn = "ou=users,dc=example,dc=org",
                    attribute = attr,
                })
                ngx.say(attr, ": ", ok and "passed" or "rejected")
            end
        }
    }
--- response_body
sAMAccountName: passed
cn;lang-en: passed
1.2.840.113556.1.4.656: passed
0.9.2342.19200300.100.1.1;binary: passed



=== TEST 44: malformed attribute forms are rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local cases = {
                "1",        -- a bare number is neither a descriptor nor an OID
                "1.2.",     -- trailing dot
                "01.2",     -- leading zero in an arc
                "cn;",      -- empty option
                ";binary",  -- missing attribute type
            }
            for _, attr in ipairs(cases) do
                local ok = plugin.check_schema({
                    ldap_uri = "127.0.0.1:1389",
                    base_dn = "ou=users,dc=example,dc=org",
                    attribute = attr,
                })
                ngx.say(attr, ": ", ok and "passed" or "rejected")
            end
        }
    }
--- response_body
1: rejected
1.2.: rejected
01.2: rejected
cn;: rejected
;binary: rejected



=== TEST 45: set up the search-then-bind route with the uid attribute's numeric OID
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "0.9.2342.19200300.100.1.1"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 46: OID attribute resolves the user end-to-end (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 47: a proxy's own Basic Proxy-Authorization must not mask a valid Authorization
--- request
GET /hello
--- more_headers
Proxy-Authorization: Basic cHJveHk6aHVudGVyMg==
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 48: Proxy-Authorization alone carries the credential (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 49: when both headers parse, Proxy-Authorization wins (proxy: user01, auth: jdoe)
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body
hello world



=== TEST 50: undecodable Proxy-Authorization payload falls back to Authorization
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap !!!not-base64!!!
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 51: unusable Proxy-Authorization with no Authorization still 401s
--- request
GET /hello
--- more_headers
Proxy-Authorization: Basic cHJveHk6aHVudGVyMg==
--- error_code: 401



=== TEST 52: Proxy-Authorization with an empty username falls back to Authorization (proxy: ":pass")
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap OnBhc3M=
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 53: Proxy-Authorization with an empty password falls back to Authorization (proxy: "user:")
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap dXNlcjo=
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 54: an empty-field Proxy-Authorization with no Authorization still 401s (proxy: ":")
--- request
GET /hello
--- more_headers
Proxy-Authorization: ldap Og==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 55: set up a route whose service-account password is wrong
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "bind_dn": "cn=admin,dc=example,dc=org",
                            "ldap_password": "rotated-away"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 56: rejected service bind -> 500, never a client auth failure (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP search bind failed



=== TEST 57: set up a route with a nonexistent base_dn
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=nowhere,dc=example,dc=org",
                            "attribute": "uid"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 58: search against a nonexistent base_dn -> 500 (noSuchObject is a misconfiguration) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP user search failed



=== TEST 59: set up a route whose login attribute matches many entries (objectClass)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "objectClass"
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 60: sizeLimitExceeded stays a fail-closed 401, not a 500 (creds: inetOrgPerson:x)
--- request
GET /hello
--- more_headers
Authorization: ldap aW5ldE9yZ1BlcnNvbjp4
--- error_code: 401
--- grep_error_log eval
qr/ambiguous user match \(size limit exceeded\)/
--- grep_error_log_out
ambiguous user match (size limit exceeded)



=== TEST 61: empty ldap_uri is rejected (minLength)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "",
                base_dn = "ou=users,dc=example,dc=org",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/property "ldap_uri" validation failed/



=== TEST 62: overlong base_dn is rejected (maxLength)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=" .. string.rep("x", 4094) .. ",dc=org",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/property "base_dn" validation failed/



=== TEST 63: set up the /hello route with a log-phase identity-header reader
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "set_user_dn_header": true
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"ldapheaders: [\", ctx.var.http_x_authenticated_username, \"][\", ctx.var.http_x_authenticated_user_dn, \"][\", ctx.var.http_x_authenticated_groups, \"]\") end"]
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 64: identity headers reach a log-phase reader as $http_ vars (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log eval
qr/ldapheaders: \[user01\]\[cn=user01,ou=users,dc=example,dc=org\]\[(Domain Admins,developers|developers,Domain Admins)\]/



=== TEST 65: X-Authenticated-User-Dn and X-Authenticated-Username reach the upstream (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-user-dn: cn=user01,ou=users,dc=example,dc=org\nx-authenticated-username: user01\n/



=== TEST 66: a lower-priority plugin's _meta.filter can match the identity header via $http_
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "set_user_dn_header": true
                        },
                        "response-rewrite": {
                            "_meta": {
                                "filter": [["http_x_authenticated_user_dn", "==", "cn=user01,ou=users,dc=example,dc=org"]]
                            },
                            "body": "var-filter-hit\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/uri"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 67: the filter fires for user01 and stays quiet for jdoe
--- pipelined_requests eval
["GET /uri", "GET /uri"]
--- more_headers eval
["Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==", "Authorization: ldap amRvZTpqYW5lc2VjcmV0"]
--- response_body_like eval
[qr/var-filter-hit/, qr/uri: \/uri/]



=== TEST 68: set up a multi-auth route where a denied LDAP principal is followed by a key-auth win
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "ldapadvmixed",
                    "plugins": {
                        "key-auth": {
                            "key": "ldapadv-mixed-key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code2, body2 = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "ldap-auth-advanced": {
                                        "ldap_uri": "127.0.0.1:1389",
                                        "base_dn": "ou=users,dc=example,dc=org",
                                        "attribute": "uid",
                                        "groups_required": [["no-such-group"]]
                                    }
                                },
                                {
                                    "key-auth": {}
                                }
                            ]
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"ldapheaders: [\", ctx.var.http_x_authenticated_username, \"][\", ctx.var.http_x_authenticated_user_dn, \"][\", ctx.var.http_x_authenticated_groups, \"]\") end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]=]
                )
            if code2 >= 300 then
                ngx.status = code2
            end
            ngx.say(body2)
        }
    }
--- response_body
passed



=== TEST 69: a denied LDAP principal leaves no identity headers behind for a sibling key-auth win (creds: user01:password1 + apikey)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
apikey: ldapadv-mixed-key
--- error_code: 200
--- error_log eval
qr/ldapheaders: \[nil\]\[nil\]\[nil\]/



=== TEST 70: attaching ldap-auth-advanced to a Consumer is rejected with a pointer to ldap-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- the slice-1 consumer shape: exactly what a stale pre-release
            -- Consumer would still carry
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "ldapadvnoconsumer",
                    "plugins": {
                        "ldap-auth-advanced": {
                            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
                        }
                    }
                }]]
                )
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/does not support consumer-scoped configuration; use the ldap-auth plugin/



=== TEST 71: a Credential carrying ldap-auth-advanced is rejected the same way
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- a plugin-less Consumer is fine; only the credential must fail
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{ "username": "ldapadvcredcase" }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
            local code2, body2 = t(
                '/apisix/admin/consumers/ldapadvcredcase/credentials/cred1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
                        }
                    }
                }]]
                )
            ngx.say(code2)
            ngx.print(body2)
            t('/apisix/admin/consumers/ldapadvcredcase', ngx.HTTP_DELETE)
        }
    }
--- response_body_like eval
qr/^400\n.*does not support consumer-scoped configuration/
