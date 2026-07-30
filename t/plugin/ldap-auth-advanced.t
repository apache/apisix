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



=== TEST 12: consumer schema with user_dn passes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { user_dn = "cn=user01,ou=users,dc=example,dc=org" },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 13: empty consumer schema is rejected
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({}, core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 14: set up a route protected by ldap-auth-advanced (live LDAP)
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



=== TEST 15: no credential header -> 401 with WWW-Authenticate ldap realm
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: ldap realm="ldap"



=== TEST 16: malformed base64 payload ("aca_a" does not decode) -> 401
--- request
GET /hello
--- more_headers
Authorization: ldap aca_a
--- error_code: 401



=== TEST 17: base64 payload without a ':' separator (decodes to "useronly") -> 401
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcm9ubHk=
--- error_code: 401



=== TEST 18: empty password (payload decodes to "user01:") rejected before any bind (RFC 4513 5.1.2 unauthenticated bind)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 19: scheme word parsed case-insensitively (uppercase), empty password still rejected (creds: user01:)
--- request
GET /hello
--- more_headers
Authorization: LDAP dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 20: scheme word parsed case-insensitively (mixed case), empty password still rejected (creds: user01:)
--- request
GET /hello
--- more_headers
Authorization: lDaP dXNlcjAxOg==
--- error_code: 401
--- grep_error_log eval
qr/empty password/
--- grep_error_log_out
empty password



=== TEST 21: set up a route with header_type basic
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



=== TEST 22: header_type basic emits a Basic-scheme WWW-Authenticate
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: basic realm="ldap"



=== TEST 23: inbound X-Authenticated-Groups is cleared before any auth work, on every path
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ctx = { var = {} }
            local before = core.request.header(ctx, "X-Authenticated-Groups") or "nil"
            -- no credential header -> auth_failed path; the strip must still happen
            plugin.rewrite({ header_type = "ldap", realm = "ldap" }, ctx)
            local after = core.request.header(ctx, "X-Authenticated-Groups") or "nil"
            ngx.say("before: ", before)
            ngx.say("after: ", after)
        }
    }
--- more_headers
X-Authenticated-Groups: injected
--- response_body
before: injected
after: nil



=== TEST 24: set up a route with multi-auth wrapping ldap-auth-advanced and basic-auth
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



=== TEST 25: under multi-auth ldap-auth-advanced declines quietly (creds: user01:)
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



=== TEST 26: set up the plain search-then-bind route (uid attribute)
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



=== TEST 27: consumer_required (default true) with NO matching Consumer -> 401 (fails closed) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 401
--- grep_error_log eval
qr/no Consumer is configured/
--- grep_error_log_out
no Consumer is configured



=== TEST 28: create the ldap-auth-advanced Consumers (user_dn associations)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local users = {
                { name = "ldapadvuser01", dn = "cn=user01,ou=users,dc=example,dc=org" },
                { name = "ldapadvuser02", dn = "cn=user02,ou=users,dc=example,dc=org" },
                { name = "ldapadvjdoe",   dn = "cn=Jane Doe,ou=users,dc=example,dc=org" },
                { name = "ldapadvsecret", dn = "cn=Secret User,ou=users,dc=example,dc=org" },
            }
            for _, u in ipairs(users) do
                local code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    core.json.encode({
                        username = u.name,
                        plugins = {
                            ["ldap-auth-advanced"] = { user_dn = u.dn },
                        },
                    }))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 29: happy path -- uid=user01 (cn=user01) matches Consumer ldapadvuser01 (200 + attached) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world
--- error_log
find consumer ldapadvuser01



=== TEST 30: AD-shape happy path -- uid=jdoe (cn=Jane Doe) matches Consumer ldapadvjdoe (200) (creds: jdoe:janesecret)
--- request
GET /hello
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body
hello world
--- error_log
find consumer ldapadvjdoe



=== TEST 31: wrong password -> 401 (a result-code failure, not a transport error) (creds: user01:wrong)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOndyb25n
--- error_code: 401



=== TEST 32: unknown user -> 401 (the user search returns 0 entries) (creds: nouser:x)
--- request
GET /hello
--- more_headers
Authorization: ldap bm91c2VyOng=
--- error_code: 401



=== TEST 33: ambiguous match (two uid=dupuser entries) -> 401 + "ambiguous" warn (creds: dupuser:duppass1)
--- request
GET /hello
--- more_headers
Authorization: ldap ZHVwdXNlcjpkdXBwYXNzMQ==
--- error_code: 401
--- grep_error_log eval
qr/ambiguous user match/
--- grep_error_log_out
ambiguous user match



=== TEST 34: set up the search-then-bind route with consumer_required=false
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
                            "consumer_required": false
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



=== TEST 35: consumer_required=false -> user01 authenticated, no Consumer attached (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world
--- no_error_log
find consumer



=== TEST 36: point the route at a dead LDAP port (transport-error case)
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



=== TEST 37: LDAP unreachable -> 500 (a transport error is never an auth failure) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP connect failed



=== TEST 38: set up an LDAPS route on 1636 (use_ldaps, ssl_verify off)
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



=== TEST 39: happy path over LDAPS (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 40: set up a StartTLS route on 1389 (use_starttls, ssl_verify off)
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



=== TEST 41: happy path over StartTLS (200) (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 42: restore the plain search-then-bind route for the injection suite
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



=== TEST 43: filter-injection usernames each 401 (none widens the search)
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



=== TEST 44: username with an invalid UTF-8 byte -> clean 401, never a 500
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



=== TEST 45: well-formed multibyte UTF-8 username reaches the search and 401s as not-found
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



=== TEST 46: username with a grammar-reserved ASCII byte (trailing '~') -> clean 401, never a 500
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local port = ngx.var.server_port
            -- "admin~" is valid ASCII (it passes any UTF-8 check) but filter.escape
            -- leaves '~' untouched and the library's filter grammar rejects a trailing
            -- '~' as a "syntax error". Before the compile pre-check this reached the
            -- search and the non-result-code branch turned that "syntax error" into
            -- HTTP 500. A malformed username is a bad credential (a client error),
            -- so it must be rejected up front as a clean 401 with "invalid username"
            -- -- never surfaced as a 500 and never logged as an LDAP search failure.
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
invalid username
--- no_error_log
LDAP user search failed



=== TEST 47: set up the three concurrent-probe routes (churn + anon-secret + svc-secret)
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



=== TEST 48: CONCURRENT bind-state-leak probe: anon re-bind must not leak
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
