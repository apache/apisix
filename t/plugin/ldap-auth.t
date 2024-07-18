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
BEGIN {
    $ENV{VAULT_TOKEN} = "root";
}

use t::APISIX 'no_plan';

repeat_each(2);
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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({user_dn = 'foo'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: using default value use_tls = false should give security warning
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema(
                {
                    base_dn = "123",
                    ldap_uri = "127.0.0.1:1389",
                    tls_verify = false,
                    use_tls = false
                })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Keeping tls_verify disabled in ldap-auth configuration is a security risk
Keeping use_tls disabled in ldap-auth configuration is a security risk



=== TEST 3: `use_tls = true` should not give security warning
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({base_dn = "123", ldap_uri = "127.0.0.1:1389", use_tls = true})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using LDAP auth with TLS disabled is a security risk



=== TEST 4: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({base_dn = 123, ldap_uri = "127.0.0.1:1389"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body_like eval
qr/wrong type: expected string, got number
done
/



=== TEST 5: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "user01",
                    "plugins": {
                        "ldap-auth": {
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



=== TEST 6: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
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



=== TEST 7: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 8: verify, invalid basic authorization header
--- request
GET /hello
--- more_headers
Authorization: Bad_header Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}
--- grep_error_log eval
qr/Invalid authorization header format/
--- grep_error_log_out
Invalid authorization header format



=== TEST 9: verify, invalid authorization value (bad base64 str)
--- request
GET /hello
--- more_headers
Authorization: Basic aca_a
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}
--- grep_error_log eval
qr/Failed to decode authentication header: aca_a/
--- grep_error_log_out
Failed to decode authentication header: aca_a



=== TEST 10: verify, invalid authorization value (no password)
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9v
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}
--- grep_error_log eval
qr/Split authorization err: invalid decoded data: foo/
--- grep_error_log_out
Split authorization err: invalid decoded data: foo



=== TEST 11: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}
--- error_log
The supplied credential is invalid



=== TEST 12: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 13: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
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



=== TEST 14: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 15: invalid schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {},
                "blah"
            }) do
                local code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    {
                        username = "foo",
                        plugins = {
                            ["ldap-auth"] = case
                        }
                    }
                )
                ngx.print(body)
            end
        }
    }
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin ldap-auth err: property \"user_dn\" is required"}
{"error_msg":"invalid plugins configuration: invalid plugin conf \"blah\" for plugin [ldap-auth]"}



=== TEST 16: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with route or service object","required":["base_dn","ldap_uri"],"properties":{"base_dn":{"type":"string"},"ldap_uri":{"type":"string"},"use_tls":{"type":"boolean"},"tls_verify":{"type":"boolean"},"uid":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 17: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","required":["user_dn"],"properties":{"user_dn":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 18: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with route or service object","required":["base_dn","ldap_uri"],"properties":{"base_dn":{"type":"string"},"ldap_uri":{"type":"string"},"use_tls":{"type":"boolean"},"tls_verify":{"type":"boolean"},"uid":{"type":"string"}},"type":"object"}                ]]
                )
            ngx.status = code
        }
    }



=== TEST 19: enable ldap-auth with tls
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "test.com:1636",
                            "uid": "cn",
                            "use_tls": true
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



=== TEST 20: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 21: enable ldap-auth with tls, verify CA
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "test.com:1636",
                            "uid": "cn",
                            "use_tls": true,
                            "tls_verify": true
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



=== TEST 22: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 23: set ldap-auth conf: user_dn uses secret ref
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "root"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- change consumer with secrets ref: vault
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "user01",
                    "plugins": {
                        "ldap-auth": {
                            "user_dn": "$secret://vault/test1/user01/user_dn"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- set route
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
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



=== TEST 24: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/user01 user_dn="cn=user01,ou=users,dc=example,dc=org"
--- response_body
Success! Data written to: kv/apisix/user01



=== TEST 25: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 26: set ldap-auth conf with the token in an env var: user_dn uses secret ref
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "$ENV://VAULT_TOKEN"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            -- change consumer with secrets ref: vault
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "user01",
                    "plugins": {
                        "ldap-auth": {
                            "user_dn": "$secret://vault/test1/user01/user_dn"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            -- set route
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
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



=== TEST 27: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01
