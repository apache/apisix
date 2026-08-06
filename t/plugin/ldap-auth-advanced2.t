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

=== TEST 1: group schema fields default correctly (cn / member / memberOf)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local conf = {
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_base_dn = "ou=groups,dc=example,dc=org",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.group_name_attribute, " ",
                    conf.group_member_attribute, " ",
                    conf.user_membership_attribute)
        }
    }
--- response_body
cn member memberOf



=== TEST 2: group_name_attribute with a bad pattern is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_base_dn = "ou=groups,dc=example,dc=org",
                group_name_attribute = "a b",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 3: group_member_attribute with a bad pattern is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_base_dn = "ou=groups,dc=example,dc=org",
                group_member_attribute = "1bad",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 4: user_membership_attribute with a bad pattern is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                user_membership_attribute = "has space",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 5: set up the three group-collection routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "ldap_debug": true
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/hello"
            }]])
            local code2 = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "ldap_debug": true
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            local code3 = t('/apisix/admin/routes/3', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "ldap_debug": true
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



=== TEST 6: user01 via the SEARCH path collects Domain Admins + developers (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world
--- error_log
groups:
Domain Admins
developers



=== TEST 7: user01 via the memberOf path collects Domain Admins + developers (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log
groups:
Domain Admins
developers



=== TEST 8: jdoe (space in the login->cn) via the SEARCH path collects Domain Admins + ops (creds: jdoe:janesecret)
--- request
GET /hello
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body
hello world
--- error_log
groups:
Domain Admins
ops



=== TEST 9: jdoe via the memberOf path collects Domain Admins + ops (space in the group RDN value) (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- error_log
groups:
Domain Admins
ops



=== TEST 10: user02 via the SEARCH path collects superadmin only (creds: user02:password2)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200
--- response_body
hello world
--- error_log
groups: superadmin



=== TEST 11: user02 via the memberOf path collects superadmin only (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200
--- error_log
groups: superadmin



=== TEST 12: fixture ACL check -- the group member attribute is identity-dependent
--- config
    location /t {
        content_by_lua_block {
            -- Fixture ACL: `member` is readable by the configured identity
            -- (anonymous) but not by a regular end user, so this search only
            -- resolves groups when bound as the configured identity -- proving
            -- the re-bind test is non-vacuous (a skipped re-bind would collect 0).
            local client = require("resty.ldap.client")
            local protocol = require("resty.ldap.protocol")
            local filter = require("resty.ldap.filter")

            local function member_hits(bind_dn, bind_pw)
                local c = client:new("127.0.0.1", 1389, { socket_timeout = 3000 })
                assert(c:simple_bind(bind_dn, bind_pw))
                local entries = assert(c:search(
                    "ou=groups,dc=example,dc=org",
                    protocol.SEARCH_SCOPE_WHOLE_SUBTREE,
                    protocol.SEARCH_DEREF_ALIASES_ALWAYS,
                    10, 5, false,
                    "(member=" .. filter.escape(
                        "cn=user01,ou=users,dc=example,dc=org") .. ")",
                    { "cn" }))
                c:close()
                local n = 0
                for _, e in ipairs(entries) do
                    if e.entry_dn then n = n + 1 end
                end
                return n
            end

            ngx.say("end_user_hits: ",
                    member_hits("cn=user01,ou=users,dc=example,dc=org", "password1"))
            ngx.say("anonymous_hits: ", member_hits("", ""))
        }
    }
--- response_body
end_user_hits: 0
anonymous_hits: 2



=== TEST 13: user01 on the anonymous-rebind SEARCH route still collects its groups (creds: user01:password1)
--- request
GET /hello1
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log
groups:
Domain Admins
developers



=== TEST 14: multiuser via the SEARCH path collects ALL three groups (unbounded group search) (creds: multiuser:multipass)
--- request
GET /hello
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body
hello world
--- error_log
groups:
Domain Admins
developers
ops



=== TEST 15: multiuser via the memberOf path also collects all three groups (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- error_log
groups:
Domain Admins
developers
ops



=== TEST 16: groups_required (outer OR of inner ANDs) is a valid schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{"Domain Admins", "ops"}, {"superadmin"}},
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 17: groups_required that is not an array is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = "superadmin",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 18: groups_required with an empty inner array is rejected (inner minItems 1)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{}},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 19: groups_required with a non-string group name is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{123}},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 20: set up the groups_required route (memberOf path, /uri echoes the outbound header)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "groups_required": [["Domain Admins", "ops"], ["superadmin"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: jdoe satisfies inner AND [Domain Admins, ops] -> 200 + outbound header carries both names (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
X-Authenticated-Groups: injected
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (Domain Admins,ops|ops,Domain Admins)\n/
--- response_body_unlike eval
qr/injected/



=== TEST 22: user01 (Domain Admins + developers) satisfies no inner AND -> 403, distinct from the 401 body (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
X-Authenticated-Groups: injected
--- error_code: 403
--- response_body
{"message":"Forbidden"}
--- response_headers
X-Authenticated-Groups:
--- grep_error_log eval
qr/groups_required not satisfied/
--- grep_error_log_out
groups_required not satisfied



=== TEST 23: user02 satisfies the OR alternate [superadmin] -> 200 + exact single-group header (inbound stripped) (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
X-Authenticated-Groups: injected
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: superadmin\n/
--- response_body_unlike eval
qr/injected/



=== TEST 24: on the groups_required route a wrong password -> 401 body, distinct from the 403 body, no outbound header (creds: user01:wrong)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOndyb25n
X-Authenticated-Groups: injected
--- error_code: 401
--- response_body
{"message":"Authorization required"}
--- response_headers
X-Authenticated-Groups:



=== TEST 25: set up a groups_required route with a space-containing name in the OR position
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "groups_required": [["developers"], ["Domain Admins"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 26: jdoe passes via the space-containing OR alternate "Domain Admins" (verbatim match, space preserved) (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (Domain Admins,ops|ops,Domain Admins)\n/



=== TEST 27: set up a groups_required route with a space-containing name inside an inner AND
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "groups_required": [["Domain Admins", "developers"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 28: user01 satisfies the inner AND [Domain Admins, developers] (space-containing AND term) -> 200 (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (Domain Admins,developers|developers,Domain Admins)\n/



=== TEST 29: user02 (superadmin only) fails the inner AND [Domain Admins, developers] -> 403 (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 403
--- response_body
{"message":"Forbidden"}



=== TEST 30: set up a groups_required route whose required name differs only by case
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "groups_required": [["domain admins"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 31: "domain admins" does NOT match the collected "Domain Admins" -> 403 (no case folding) (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 403
--- response_body
{"message":"Forbidden"}
--- grep_error_log eval
qr/groups_required not satisfied/
--- grep_error_log_out
groups_required not satisfied



=== TEST 32: point a groups_required route at a dead LDAP port (transport-error case)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1390",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "timeout": 1000,
                    "groups_required": [["superadmin"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 33: LDAP unreachable -> 500 and the outbound header is absent (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
X-Authenticated-Groups: injected
--- error_code: 500
--- response_headers
X-Authenticated-Groups:
--- error_log
LDAP connect failed



=== TEST 34: set up the unescape-observation routes (comma-in-cn group "Sales, EMEA")
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "ldap_debug": true
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/hello"
            }]])
            -- OpenLDAP renders the comma in "Sales, EMEA" hex-escaped in the
            -- memberOf DN (cn=Sales\2C EMEA); TEST 36 checks it unescapes back.
            local code2 = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "ldap_debug": true
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            local ok = code < 300 and code2 < 300
            ngx.say(ok and "passed" or "failed")
        }
    }
--- response_body
passed



=== TEST 35: salesuser via the SEARCH path -- group NAME is the cn value "Sales, EMEA" (creds: salesuser:salespass)
--- request
GET /hello
--- more_headers
Authorization: ldap c2FsZXN1c2VyOnNhbGVzcGFzcw==
--- error_code: 200
--- response_body
hello world
--- error_log
groups: Sales, EMEA



=== TEST 36: salesuser via the memberOf path -- UNESCAPED first RDN equals the SEARCH-path name "Sales, EMEA" (creds: salesuser:salespass)
--- request
GET /uri
--- more_headers
Authorization: ldap c2FsZXN1c2VyOnNhbGVzcGFzcw==
X-Authenticated-Groups: injected
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: Sales, EMEA\n/
--- response_body_unlike eval
qr/Sales\\2C EMEA|injected/
--- error_log
groups: Sales, EMEA



=== TEST 37: set up the /uri route with a service bind, no group_base_dn, for the no-groups header-omission check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- secretuser is invisible to an anonymous search (fixture ACL), so
            -- this route needs a service bind_dn to resolve it at all.
            local code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword"
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 38: a zero-group user reaches the upstream with no X-Authenticated-Groups (empty value is dropped), inbound value still stripped (creds: secretuser:secretpass)
--- request
GET /uri
--- more_headers
Authorization: ldap c2VjcmV0dXNlcjpzZWNyZXRwYXNz
X-Authenticated-Groups: injected
--- error_code: 200
--- response_body_unlike eval
qr/x-authenticated-groups|injected/



=== TEST 39: point the /uri route's group search at a nonexistent base DN (group-search-failure case)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=nogroups,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword"
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 40: user01 authenticates but the group search against a nonexistent base DN fails -> 500 (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP group search failed



=== TEST 41: group_name_attribute set without group_base_dn is rejected (memberOf path ignores it)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_name_attribute = "displayName",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
group_name_attribute is only used with group_base_dn



=== TEST 42: group_member_attribute set without group_base_dn is rejected (memberOf path ignores it)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_member_attribute = "uniqueMember",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
group_member_attribute is only used with group_base_dn



=== TEST 43: both group attributes set alongside group_base_dn pass (SEARCH path uses them)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_base_dn = "ou=groups,dc=example,dc=org",
                group_name_attribute = "displayName",
                group_member_attribute = "uniqueMember",
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 44: REGRESSION GUARD -- re-validating stored config (defaults already injected) still passes, not a naive presence check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local conf = {
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
            }
            local ok1 = plugin.check_schema(conf)
            -- conf now carries injected defaults; re-validating the SAME table
            -- simulates APISIX re-checking already-stored config on reload.
            local ok2 = plugin.check_schema(conf)
            ngx.say(ok1 and "passed" or "rejected", " ", ok2 and "passed" or "rejected")
        }
    }
--- response_body
passed passed



=== TEST 45: set up a groups_required route on the SEARCH path (group_base_dn + service bind)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "groups_required": [["Domain Admins", "developers"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/hello"
            }]=])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 46: user01 satisfies the inner AND [Domain Admins, developers] via the SEARCH path (cn-derived names) -> 200 (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body
hello world



=== TEST 47: user02 (superadmin only) fails the inner AND [Domain Admins, developers] via the SEARCH path -> 403 (creds: user02:password2)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 403
--- response_body
{"message":"Forbidden"}



=== TEST 48: set up a groups_required route with a log-phase identity-header reader
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "group_base_dn": "ou=groups,dc=example,dc=org",
                            "bind_dn": "cn=admin,dc=example,dc=org",
                            "ldap_password": "adminpassword",
                            "groups_required": [["Domain Admins"]],
                            "set_user_dn_header": true
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"ldapheaders2: [\", ctx.var.http_x_authenticated_username, \"][\", ctx.var.http_x_authenticated_user_dn, \"][\", ctx.var.http_x_authenticated_groups, \"]\") end"]
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 49: authorized user exports identity headers on the 200 path (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log eval
qr/ldapheaders2: \[user01\]\[cn=user01,ou=users,dc=example,dc=org\]\[(Domain Admins,developers|developers,Domain Admins)\]/



=== TEST 50: no identity is exported when authorization denies with 403; the warn names the denied user (creds: user02:password2)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 403
--- error_log eval
[qr/ldapheaders2: \[nil\]\[nil\]\[nil\]/, qr/groups_required not satisfied for cn=user02,ou=users,dc=example,dc=org/]



=== TEST 51: identity-export toggles default to username on, user DN off, groups on
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local conf = {
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(tostring(conf.set_username_header), " ",
                    tostring(conf.set_user_dn_header), " ",
                    tostring(conf.set_groups_header))
        }
    }
--- response_body
true false true



=== TEST 52: set up a default-toggles route with a log-phase identity-header reader
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid"
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"ldapheaders3: [\", ctx.var.http_x_authenticated_username, \"][\", ctx.var.http_x_authenticated_user_dn, \"][\", ctx.var.http_x_authenticated_groups, \"]\") end"]
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 53: by default the username and groups export, the user DN does not (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log eval
qr/ldapheaders3: \[user01\]\[nil\]\[(Domain Admins,developers|developers,Domain Admins)\]/



=== TEST 54: set up a route exporting ONLY the user DN (username and groups toggled off)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "set_username_header": false,
                            "set_user_dn_header": true,
                            "set_groups_header": false
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"ldapheaders4: [\", ctx.var.http_x_authenticated_username, \"][\", ctx.var.http_x_authenticated_user_dn, \"][\", ctx.var.http_x_authenticated_groups, \"]\") end"]
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 55: only X-Authenticated-User-Dn reaches the reader; username and groups stay nil (creds: user01:password1)
--- request
GET /hello
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- error_log eval
qr/ldapheaders4: \[nil\]\[cn=user01,ou=users,dc=example,dc=org\]\[nil\]/
