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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casbin")
            local conf = {
                model_path = "/path/to/model.conf",
                policy_path = "/path/to/policy.csv",
                username = "user"
            }
            local ok, err = plugin.check_schema(conf)
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



=== TEST 2: username missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casbin")
            local conf = {
                model_path = "/path/to/model.conf",
                policy_path = "/path/to/policy.csv"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "username" is required
--- no_error_log
[error]



=== TEST 3: put model and policy text in metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casbin")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/authz-casbin',
                ngx.HTTP_PUT,
                [[{
                    "model": "[request_definition]
                    r = sub, obj, act

                    [policy_definition]
                    p = sub, obj, act

                    [role_definition]
                    g = _, _

                    [policy_effect]
                    e = some(where (p.eft == allow))

                    [matchers]
                    m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

                    "policy": "p, *, /, GET
                    p, admin, *, *
                    g, alice, admin"
                }]]
                )

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: Enforcer from text without files
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casbin")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/authz-casbin',
                ngx.HTTP_PUT,
                [[{
                    "model": "[request_definition]
                    r = sub, obj, act

                    [policy_definition]
                    p = sub, obj, act

                    [role_definition]
                    g = _, _

                    [policy_effect]
                    e = some(where (p.eft == allow))

                    [matchers]
                    m = (g(r.sub, p.sub) || keyMatch(r.sub, p.sub)) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)",

                    "policy": "p, *, /, GET
                    p, admin, *, *
                    g, alice, admin"
                }]]
                )

            local conf = {
                username = "user"
            }
            local ok, err = plugin.check_schema(conf)
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



=== TEST 5: enable authz-casbin by Admin API
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "authz-casbin": {
                            "username" : "user"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: no username header passed
--- request
GET /hello
--- error_code: 403
--- response_body_like eval
qr/"Access Denied"/
--- no_error_log
[error]



=== TEST 7: username passed but user not authorized
--- request
GET /hello
--- more_headers
user: bob
--- error_code: 403
--- response_body
{"message":"Access Denied"}
--- no_error_log
[error]



=== TEST 8: authorized user
--- request
GET /hello
--- more_headers
user: admin
--- error_code: 200
--- response_body
hello world
--- no_error_log
[error]



=== TEST 9: authorized user (rbac)
--- request
GET /hello
--- more_headers
user: alice
--- error_code: 200
--- response_body
hello world
--- no_error_log
[error]



=== TEST 10: invalid policy addition: enforcer not created
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/plugin/authz-casbin/add',
                ngx.HTTP_POST,
                [[{

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
--- error_code: 400
--- response_body_like eval
qr/"Enforcer not created yet."/
--- no_error_log
[error]



=== TEST 11: invalid policy addition: type not passed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello',
                ngx.HTTP_GET,
                [[{

                }]]
                )

            local code, body = t('/apisix/plugin/authz-casbin/add',
                ngx.HTTP_POST,
                [[{

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
--- error_code: 400
--- response_body_like eval
qr/"Invalid policy type."/
--- no_error_log
[error]



=== TEST 12: invalid policy addition: invalid policy format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body = t('/apisix/plugin/authz-casbin/add',
                ngx.HTTP_POST, nil, nil,
                {
                    ["type"] = "p",
                    ["subject"] = "none"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like eval
qr/"Invalid policy request."/
--- no_error_log
[error]



=== TEST 13: user not authorized before policy addition
--- request
GET /hello
--- more_headers
user: jack
--- error_code: 403
--- response_body
{"message":"Access Denied"}
--- no_error_log
[error]



=== TEST 14: valid policy addition
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body = t('/apisix/plugin/authz-casbin/add',
                ngx.HTTP_POST, nil, nil,
                {
                    ["type"] = "p",
                    ["subject"] = "jack",
                    ["object"] = "/hello",
                    ["action"] = "GET"
                }
                )
                
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]




=== TEST 15: user authorized after policy addition
--- request
GET /hello
--- more_headers
user: jack
--- error_code: 200
--- response_body
hello world
--- no_error_log
[error]



=== TEST 16: user still unauthorized for non-GET request as per the policy
--- request
POST /hello
--- more_headers
user: jack
--- error_code: 403
--- response_body
{"message":"Access Denied"}
--- no_error_log
[error]




=== TEST 17: valid policy removal
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, _ = t('/hello', ngx.HTTP_GET)
            
            local code, body = t('/apisix/plugin/authz-casbin/remove',
                ngx.HTTP_POST, nil, nil,
                {
                    ["type"] = "p",
                    ["subject"] = "jack",
                    ["object"] = "/hello",
                    ["action"] = "GET"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 18: user unauthorized after policy removal
--- request
GET /hello
--- more_headers
user: jack
--- error_code: 403
--- response_body
{"message":"Access Denied"}
--- no_error_log
[error]



=== TEST 19: invalid policy removal: no such policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, _ = t('/hello', ngx.HTTP_GET)
            
            local code, body = t('/apisix/plugin/authz-casbin/remove',
                ngx.HTTP_POST, nil, nil,
                {
                    ["type"] = "p",
                    ["subject"] = "jack",
                    ["object"] = "/hello",
                    ["action"] = "GET"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like eval
qr/"Invalid policy request."/
--- no_error_log
[error]



=== TEST 20: get policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body, body_text = t('/apisix/plugin/authz-casbin/get',
                ngx.HTTP_GET, nil, nil,
                {
                    ["type"] = "p"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body_text)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body_like eval
qr/"data":\[\["\*","\\\/","GET"\],\["admin","\*","\*"\]\]/
--- no_error_log
[error]



=== TEST 21: get grouping policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body, body_text = t('/apisix/plugin/authz-casbin/get',
                ngx.HTTP_GET, nil, nil,
                {
                    ["type"] = "g"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body_text)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body_like eval
qr/"data":\[\["alice","admin"\]\]/
--- no_error_log
[error]



=== TEST 22: has policy: true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body, body_text = t('/apisix/plugin/authz-casbin/has',
                ngx.HTTP_GET, nil, nil,
                {
                    ["type"] = "g",
                    ["user"] = "alice",
                    ["role"] = "admin"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body_text)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body_like eval
qr/"data":"true"/
--- no_error_log
[error]



=== TEST 23: has policy: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _ = t('/hello', ngx.HTTP_GET)

            local code, body, body_text = t('/apisix/plugin/authz-casbin/has',
                ngx.HTTP_GET, nil, nil,
                {
                    ["type"] = "g",
                    ["user"] = "bob",
                    ["role"] = "admin"
                }
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body_text)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body_like eval
qr/"data":"false"/
--- no_error_log
[error]



=== TEST 24: disable authz-casbin by Admin API
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {},
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]