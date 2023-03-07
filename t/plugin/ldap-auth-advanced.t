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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity (route)
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {ldap_uri = "127.0.0.1:1389", user_dn_template = "cn=%s,ou=users,dc=example,dc=com"},
                {ldap_uri = "127.0.0.1:1389"},
                {user_dn_template = "cn=%s,ou=users,dc=example,dc=com"},
                {ldap_uri = "127.0.0.1:1389", user_dn_template = "cn=jack,ou=users,dc=example,dc=com"},
                {ldap_uri = "127.0.0.1:1389", user_dn_template = "cn=%s,ou=users,dc=example,dc=com", use_starttls = true},
                {ldap_uri = "127.0.0.1:1389", user_dn_template = "cn=%s,ou=users,dc=example,dc=com", use_starttls = "true"},
                {ldap_uri = "127.0.0.1:1389", user_dn_template = "cn=%s,ou=users,dc=example,dc=com", use_starttls = true, use_ldaps = true},
            }
            local plugin = require("apisix.plugins.ldap-auth-advanced")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "user_dn_template" is required
property "ldap_uri" is required
User DN template doesn't contain the %s placeholder for the uid variable
done
property "use_starttls" validation failed: wrong type: expected boolean, got string
STARTTLS and LDAPS cannot be open at the same time



=== TEST 2: sanity (consumer)
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {user_dn = "cn=jack,ou=users,dc=example,dc=com"},
                {group_dn = "cn=group1,ou=groups,dc=example,dc=com"},
                {user_dn = "cn=jack,ou=users,dc=example,dc=com", group_dn = "cn=group1,ou=groups,dc=example,dc=com"},
                {user_dn = 1234},
            }
            local core   = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth-advanced")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case, core.schema.TYPE_CONSUMER)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
done
value should match only one schema, but matches both schemas 1 and 2
property "user_dn" validation failed: wrong type: expected string, got number



=== TEST 3: create route (consumer_require = false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "user_dn_template": "cn=%s,ou=users,dc=example,dc=org",
                            "consumer_required": false
                        }
                    }
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



=== TEST 4: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 5: verify, invalid authorization value
--- request
GET /hello
--- more_headers
Authorization: Basic (())(())
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}



=== TEST 6: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3Jk
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}
--- error_log
The supplied credential is invalid



=== TEST 7: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world



=== TEST 8: create route (consumer_require = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "user_dn_template": "cn=%s,ou=users,dc=example,dc=org",
                            "consumer_required": true
                        },
                        "response-rewrite": {
                            "headers": {
                                "set": {
                                    "X-Consumer-Name": "$consumer_name"
                                }
                            }
                        }
                    }
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



=== TEST 9: create consumer (use user_dn)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "user01",
                    "plugins": {
                        "ldap-auth-advanced": {
                            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
                        }
                    }
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



=== TEST 10: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- response_headers
X-Consumer-Name: user01



=== TEST 11: create consumer (use group_dn)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "gourp01",
                    "plugins": {
                        "ldap-auth-advanced": {
                            "group_dn": "cn=group01,ou=users,dc=example,dc=org"
                        }
                    }
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



=== TEST 12: verify (user01 => user_dn consumer)
For the presence of both user_dn and group_dn matches, the user_dn takes priority.
user01 (in group01) => match consumer `user01`
user02 (in group02) => match consumer `group01`, because there is no consumer for this user itself.
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- response_headers
X-Consumer-Name: user01



=== TEST 13: verify (user02 => group_dn consumer)
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAyOnBhc3N3b3JkMg==
--- response_body
hello world
--- response_headers
X-Consumer-Name: gourp01



=== TEST 14: create route (user_membership_attribute = gidNumber)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "user_dn_template": "cn=%s,ou=users,dc=example,dc=org",
                            "user_membership_attribute": "gidNumber"
                        },
                        "response-rewrite": {
                            "headers": {
                                "set": {
                                    "X-Consumer-Name": "$consumer_name"
                                }
                            }
                        }
                    }
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



=== TEST 15: create consumer (group_dn/gidNumber = 1001)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "gourp_gid",
                    "plugins": {
                        "ldap-auth-advanced": {
                            "group_dn": "1001"
                        }
                    }
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



=== TEST 16: verify (gidNumber group consumer)
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAyOnBhc3N3b3JkMg==
--- response_body
hello world
--- response_headers
X-Consumer-Name: gourp_gid



=== TEST 17: create route (hide_credentials = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "user_dn_template": "cn=%s,ou=users,dc=example,dc=org",
                            "hide_credentials": true
                        }
                    }
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



=== TEST 18: verify, hide credentials
--- request
GET /echo HTTP/1.1
--- more_headers
Authorization: Basic dXNlcjAyOnBhc3N3b3JkMg==
--- response_headers
!Authorization



=== TEST 19: create route (ldap_debug = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "ldap-auth-advanced": {
                            "ldap_uri": "127.0.0.1:1389",
                            "user_dn_template": "cn=%s,ou=users,dc=example,dc=org",
                            "ldap_debug": true
                        }
                    }
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



=== TEST 20: verify (ldap_debug)
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAyOnBhc3N3b3JkMg==
--- response_body
hello world
--- error_log
ldap-auth-advanced user search result:
"memberOf":["cn=group01,ou=users,dc=example,dc=org"]
"entry_dn":"cn=user02,ou=users,dc=example,dc=org"
