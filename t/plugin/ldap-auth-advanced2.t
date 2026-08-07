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
                    conf.user_membership_attribute, " ",
                    tostring(conf.set_groups_header))
        }
    }
--- response_body
cn member memberOf true



=== TEST 2: group_name_attribute with a space is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
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



=== TEST 3: group_member_attribute with a space is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                group_base_dn = "ou=groups,dc=example,dc=org",
                group_member_attribute = "a b",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 4: user_membership_attribute with a space is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                user_membership_attribute = "has space",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 5: group_name_attribute without group_base_dn is rejected
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
--- response_body_like eval
qr/only used with group_base_dn/



=== TEST 6: group_member_attribute without group_base_dn is rejected
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
--- response_body_like eval
qr/only used with group_base_dn/



=== TEST 7: groups_required with valid OR-of-AND groups passes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{"Domain Admins", "ops"}, {"superadmin"}},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
passed



=== TEST 8: groups_required that is not an array is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = "Domain Admins",
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 9: groups_required with an empty inner array is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{}},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 10: groups_required with a non-string group name is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema({
                ldap_uri = "127.0.0.1:1389",
                base_dn = "ou=users,dc=example,dc=org",
                groups_required = {{"ok"}, {123}},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 11: consumer schema accepts a string group_dn
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { group_dn = "cn=Domain Admins,ou=groups,dc=example,dc=org" },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 12: consumer schema accepts an array of group_dn
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { group_dn = {"cn=developers,ou=groups,dc=example,dc=org",
                               "cn=ops,ou=groups,dc=example,dc=org"} },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 13: consumer schema rejects an empty group_dn array
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { group_dn = {} },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/value should match only one schema, but matches none/



=== TEST 14: consumer schema rejects duplicate group_dn entries
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { group_dn = {"cn=a,dc=x", "cn=a,dc=x"} },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/value should match only one schema, but matches none/



=== TEST 15: consumer schema rejects an empty string group_dn
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { group_dn = "" },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/validation failed/



=== TEST 16: consumer schema rejects both user_dn and group_dn together
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { user_dn = "cn=user01,ou=users,dc=example,dc=org",
                  group_dn = "cn=ops,ou=groups,dc=example,dc=org" },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/value should match only one schema, but matches both schemas 1 and 2/



=== TEST 17: consumer schema rejects neither user_dn nor group_dn
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")
            local ok, err = plugin.check_schema(
                { },
                core.schema.TYPE_CONSUMER)
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body_like eval
qr/value should match only one schema, but matches none/



=== TEST 18: set up route 1 for the SEARCH-path collection tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "consumer_required": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 19: user01 via the SEARCH path collects Domain Admins + developers (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*developers)/



=== TEST 20: jdoe via the SEARCH path collects Domain Admins + ops (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*ops)/



=== TEST 21: user02 via the SEARCH path collects only superadmin (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: superadmin\n/



=== TEST 22: multiuser via the SEARCH path collects Domain Admins + developers + ops (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*developers)(?=[^\n]*ops)/



=== TEST 23: salesuser via the SEARCH path collects the comma-named group unescaped (creds: salesuser:salespass)
--- request
GET /uri
--- more_headers
Authorization: ldap c2FsZXN1c2VyOnNhbGVzcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: Sales, EMEA\n/



=== TEST 24: set up route 1 for the MEMBEROF-path collection tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "consumer_required": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 25: user01 via the MEMBEROF path collects Domain Admins + developers (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*developers)/



=== TEST 26: jdoe via the MEMBEROF path collects Domain Admins + ops (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*ops)/



=== TEST 27: user02 via the MEMBEROF path collects only superadmin (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: superadmin\n/



=== TEST 28: multiuser via the MEMBEROF path collects Domain Admins + developers + ops (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*developers)(?=[^\n]*ops)/



=== TEST 29: salesuser via the MEMBEROF path collects the comma-named group unescaped (creds: salesuser:salespass; unescaped first-RDN parity between paths)
--- request
GET /uri
--- more_headers
Authorization: ldap c2FsZXN1c2VyOnNhbGVzcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: Sales, EMEA\n/



=== TEST 30: wrong password is rejected before any group collection (creds: user01:wrong)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOndyb25n
--- error_code: 401
--- response_body_unlike eval
qr/x-authenticated-groups/



=== TEST 31: set up route 1 for the SEARCH path with anonymous re-bind
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=groups,dc=example,dc=org",
                    "consumer_required": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 32: user01 via the SEARCH path with anonymous re-bind still collects groups (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups: (?=[^\n]*Domain Admins)(?=[^\n]*developers)/



=== TEST 33: set up route 1 for the service-bind MEMBEROF path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "consumer_required": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 34: zero-group user -> no groups header; forged inbound value stripped (creds: secretuser:secretpass)
--- request
GET /uri
--- more_headers
Authorization: ldap c2VjcmV0dXNlcjpzZWNyZXRwYXNz
X-Authenticated-Groups: forged-group
--- error_code: 200
--- response_body_unlike eval
qr/x-authenticated-groups/



=== TEST 35: set up the group-search-failure route (bad group_base_dn)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "group_base_dn": "ou=nowhere,dc=example,dc=org",
                    "bind_dn": "cn=admin,dc=example,dc=org",
                    "ldap_password": "adminpassword",
                    "consumer_required": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 36: authenticated user, failing group search -> 500, never 401 (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 500
--- error_log
LDAP group search failed



=== TEST 37: set up the set_groups_header=false route (memberOf path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "consumer_required": false,
                    "set_groups_header": false
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 38: set_groups_header=false hides the header though user01 has groups (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_unlike eval
qr/x-authenticated-groups/



=== TEST 39: set up the groups_required route (memberOf path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "consumer_required": false,
                    "groups_required": [["Domain Admins", "ops"], ["superadmin"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 40: jdoe satisfies the inner AND [Domain Admins, ops] (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body_like eval
qr/x-authenticated-groups:/



=== TEST 41: user01 (Domain Admins+developers) satisfies neither alternative (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 403
--- response_body_like eval
qr/Forbidden/
--- error_log
groups_required not satisfied



=== TEST 42: user02 satisfies the OR alternate [superadmin] (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200



=== TEST 43: wrong password on the authz route is 401, not 403 (creds: user01:wrong)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOndyb25n
--- error_code: 401
--- response_body_like eval
qr/Authorization required/



=== TEST 44: replace route 1's groups_required with a lowercase name (memberOf path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [=[{
                "plugins": { "ldap-auth-advanced": {
                    "ldap_uri": "127.0.0.1:1389",
                    "base_dn": "ou=users,dc=example,dc=org",
                    "attribute": "uid",
                    "consumer_required": false,
                    "groups_required": [["domain admins"]]
                } },
                "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                "uri": "/uri"
            }]=])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 45: case-mismatched group name does not match (verbatim matching, creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 403



=== TEST 46: create the group-associated Consumers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local consumers = {
                { username = "ldapg2user01",
                  conf = { user_dn = "cn=user01,ou=users,dc=example,dc=org" } },
                { username = "ldapgadmins",
                  conf = { group_dn = "cn=Domain Admins,ou=groups,dc=example,dc=org" } },
                { username = "ldapgdevs",
                  conf = { group_dn = { "cn=developers,ou=groups,dc=example,dc=org" } } },
                { username = "ldapgdevops",
                  conf = { group_dn = { "cn=developers,ou=groups,dc=example,dc=org",
                                        "cn=ops,ou=groups,dc=example,dc=org" } } },
                { username = "ldapgsuper",
                  conf = { group_dn = "cn=superadmin,ou=groups,dc=example,dc=org" } },
            }
            for _, c in ipairs(consumers) do
                local code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    core.json.encode({
                        username = c.username,
                        plugins = { ["ldap-auth-advanced"] = c.conf },
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



=== TEST 47: create the group-matching route
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
                    "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                    "uri": "/uri"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 48: user_dn precedence over group_dn consumers (creds: user01:password1)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAxOnBhc3N3b3JkMQ==
--- error_code: 200
--- response_body_like eval
qr/x-consumer-username: ldapg2user01\n/



=== TEST 49: single eligible group consumer, array must match ALL (creds: jdoe:janesecret)
--- request
GET /uri
--- more_headers
Authorization: ldap amRvZTpqYW5lc2VjcmV0
--- error_code: 200
--- response_body_like eval
qr/x-consumer-username: ldapgadmins\n/
--- no_error_log
multiple consumers matched



=== TEST 50: string-form group_dn works (creds: user02:password2)
--- request
GET /uri
--- more_headers
Authorization: ldap dXNlcjAyOnBhc3N3b3JkMg==
--- error_code: 200
--- response_body_like eval
qr/x-consumer-username: ldapgsuper\n/



=== TEST 51: deterministic pick under multiple matches (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-consumer-username: ldapgadmins\n/
--- error_log
multiple consumers matched



=== TEST 52: delete consumer ldapgadmins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/ldapgadmins', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 53: specificity tie-break, the 2-group consumer wins (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body_like eval
qr/x-consumer-username: ldapgdevops\n/
--- error_log
multiple consumers matched



=== TEST 54: delete ldapgdevops, ldapgdevs, ldapgsuper
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local names = { "ldapgdevops", "ldapgdevs", "ldapgsuper" }
            for _, name in ipairs(names) do
                local code, body = t('/apisix/admin/consumers/' .. name, ngx.HTTP_DELETE)
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



=== TEST 55: no eligible consumer, consumer_required=true -> 401 (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 401
--- error_log
no Consumer maps to the authenticated user_dn



=== TEST 56: set up route 1 with consumer_required=false
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
                    "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                    "uri": "/uri"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 57: consumer_required=false skips matching entirely (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 200
--- response_body_unlike eval
qr/x-consumer-username/



=== TEST 58: create consumer ldapgsecret with an unresolved group_dn secret ref
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                core.json.encode({
                    username = "ldapgsecret",
                    plugins = { ["ldap-auth-advanced"] = {
                        group_dn = "$ENV://ADV_LDAP_GROUP_DN_UNSET",
                    } },
                }))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 59: restore route 1 to consumer_required default (memberOf path)
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
                    "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                    "uri": "/uri"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 60: secret-ref fail-closed skips the consumer (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 401
--- error_log
skipping consumer: ldapgsecret



=== TEST 61: restore ldapgadmins and create the 403-precedence route
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                core.json.encode({
                    username = "ldapgadmins",
                    plugins = { ["ldap-auth-advanced"] = {
                        group_dn = "cn=Domain Admins,ou=groups,dc=example,dc=org",
                    } },
                }))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "base_dn": "ou=users,dc=example,dc=org",
                            "attribute": "uid",
                            "groups_required": [["no-such-group"]]
                        }
                    },
                    "upstream": { "nodes": { "127.0.0.1:1980": 1 }, "type": "roundrobin" },
                    "uri": "/uri"
                }]=])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 62: 403 from groups_required beats consumer matching (creds: multiuser:multipass)
--- request
GET /uri
--- more_headers
Authorization: ldap bXVsdGl1c2VyOm11bHRpcGFzcw==
--- error_code: 403
--- response_body_like eval
qr/Forbidden/
--- response_body_unlike eval
qr/x-consumer-username/
