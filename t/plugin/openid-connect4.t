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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: Set up new route access the auth server with header test
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
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "authorization_params":{
                                    "test":"abc"
                                },
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix",
                                "proxy_opts": {
                                    "http_proxy": "http://127.0.0.1:8080",
                                    "http_proxy_authorization": "Basic dXNlcm5hbWU6cGFzc3dvcmQK"
                                },
                                "use_pkce": false
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



=== TEST 2: Check the uri of the authorization endpoint for passed headers
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
                string.find(location, 'test=abc') ~= -1 then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302
--- error_log
use http proxy



=== TEST 3: Set an unsupported scope in the required scopes field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            require("apisix.plugins.openid-connect")
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "realm": "University",
                                "required_scopes": ["unsupported"],
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
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



=== TEST 4: Access route
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })
                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- error_log
required scopes not present



=== TEST 5: Set a supported scope in the required scopes field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            require("apisix.plugins.openid-connect")
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "realm": "University",
                                "required_scopes": ["profile"],
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
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



=== TEST 6: Access route
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })
                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- response_body
true
