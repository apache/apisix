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
--- no_error_log
[error]



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.basic-auth")
            local ok, err = plugin.check_schema({username = 123, password = "bar"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body_like eval
qr/additional properties forbidden, found (username|password)
done
/
--- no_error_log
[error]



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
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "foo",
                            "plugins": {
                                "basic-auth": {
                                    "username": "foo",
                                    "password": "bar"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 5: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 6: verify, invalid username
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Invalid user key in authorization"}
--- no_error_log
[error]



=== TEST 7: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Password is error"}
--- no_error_log
[error]



=== TEST 8: verify
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- no_error_log
[error]



=== TEST 9: invalid schema, only one field `username`
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
--- no_error_log
[error]



=== TEST 10: invalid schema, not field given
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
--- no_error_log
[error]



=== TEST 11: invalid schema, not a table
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
--- no_error_log
[error]



=== TEST 12: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"title":"work with route or service object","additionalProperties":false,"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 13: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","additionalProperties":false,"required":["username","password"],"properties":{"username":{"type":"string"},"password":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 14: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/basic-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"title":"work with route or service object","additionalProperties":false,"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]
