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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.basic-auth")
            local ok, err = plugin.check_schema({username = 'foo', password = 'bar'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.basic-auth")
            local ok, err = plugin.check_schema({username = 123, password = "bar"}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "username" validation failed: wrong type: expected string, got number
done



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
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
--- request
GET /t
--- response_body
passed



=== TEST 4: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
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
--- request
GET /t
--- response_body
passed



=== TEST 5: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 6: verify, invalid basic authorization header
--- request
GET /hello
--- more_headers
Authorization: Bad_header YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}
--- grep_error_log eval
qr/Invalid authorization header format/
--- grep_error_log_out
Invalid authorization header format



=== TEST 7: verify, invalid authorization value (bad base64 str)
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



=== TEST 8: verify, invalid authorization value (no password)
--- request
GET /hello
--- more_headers
Authorization: Basic YmFy
--- error_code: 401
--- response_body
{"message":"Invalid authorization in request"}
--- grep_error_log eval
qr/Split authorization err: invalid decoded data: bar/
--- grep_error_log_out
Split authorization err: invalid decoded data: bar



=== TEST 9: verify, invalid username
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}



=== TEST 10: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}



=== TEST 11: verify
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- error_log
find consumer foo



=== TEST 12: invalid schema, only one field `username`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo"
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin basic-auth err: property \"password\" is required"}



=== TEST 13: invalid schema, not field given
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like eval
qr/\{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin basic-auth err: property \\"(username|password)\\" is required"\}/



=== TEST 14: invalid schema, not a table
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": "blah"
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: invalid plugin conf \"blah\" for plugin [basic-auth]"}



=== TEST 15: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"title":"work with route or service object","type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t



=== TEST 16: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","required":["username","password"],"properties":{"username":{"type":"string"},"password":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t



=== TEST 17: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"title":"work with route or service object","type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t



=== TEST 18: enable basic auth plugin using admin api, set hide_credentials = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {
                            "hide_credentials": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 19: verify Authorization request header is hidden
--- request
GET /echo
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_headers
!Authorization



=== TEST 20: enable basic auth plugin using admin api, hide_credentials = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {
                            "hide_credentials": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 21: verify Authorization request header should not hidden
--- request
GET /echo
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_headers
Authorization: Basic Zm9vOmJhcg==



=== TEST 22: set basic-auth conf: password uses secret ref
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
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "$secret://vault/test1/foo/passwd"
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
                        "basic-auth": {
                            "hide_credentials": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
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



=== TEST 23: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo passwd=bar
--- response_body
Success! Data written to: kv/apisix/foo



=== TEST 24: verify Authorization with foo/bar, request header should not hidden
--- request
GET /echo
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_headers
Authorization: Basic Zm9vOmJhcg==



=== TEST 25: set basic-auth conf with the token in an env var: password uses secret ref
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
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "$secret://vault/test1/foo/passwd"
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
                        "basic-auth": {
                            "hide_credentials": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
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



=== TEST 26: verify Authorization with foo/bar, request header should not hidden
--- request
GET /echo
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_headers
Authorization: Basic Zm9vOmJhcg==
