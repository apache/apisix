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
run_tests;

__DATA__

=== TEST 1: Sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = "a", client_secret = "b", discovery = "c"})
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



=== TEST 2: Missing `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" is required
done
--- no_error_log
[error]



=== TEST 3: Wrong type for `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = 123, client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 4: Set up new route with plugin matching URI `/hello`.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10000,
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 5: Access route w/o bearer token. Should redirect to authentication endpoint of ID provider.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=https://iresty.com') ~= -1 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- timeout: 10s
--- response_body
true
--- error_code: 302
--- no_error_log
[error]



=== TEST 6: Modify route to match catch-all URI `/*` and point plugin to local Keycloak instance.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_token_header": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/foo"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                    "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "realm": "University",
                                    "introspection_endpoint_auth_method": "client_secret_post",
                                    "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                    "set_access_token_header": true,
                                    "access_token_in_authorization_header": false,
                                    "set_id_token_header": true,
                                    "set_userinfo_token_header": true
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/foo"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
