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
# no_shuffle();

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

=== TEST 1: Check configuration of cookie
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {
                    client_id = "course_management",
                    client_secret = "tbsmDOpsHwdgIqYl2NltGRTKzjIzvEmT",
                    discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                    session = {
                        secret = "6S8IO+Pydgb33LIor8T9ClER0T/sglFAjClFeAF3RsY=",
                        cookie = {
                            lifetime = 86400
                        }
                    }
                },
            }
            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done



=== TEST 2: Set up new route access the auth server
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "bearer_only" : false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "required_scopes": ["profile"],
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_header": true,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    "cookie": {
                                        "lifetime": 86400
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
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
--- response_body
passed



=== TEST 3: Call to route to get session
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local current_time = os.time()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local parts = {}
            for part in string.gmatch(cookie_str, "[^|]+") do
                table.insert(parts, part)
            end
            local target_number = tonumber(parts[2], 10) - 86400
            -- ngx.say(target_number, current_time)
            if target_number >= current_time then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 4: Update route with Keycloak introspection endpoint and introspection addon headers.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "introspection_addon_headers": ["X-Addon-Header-A", "X-Addon-Header-B"]
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



=== TEST 5: Obtain valid token and access route with it, introspection work as expected when configured extras headers.
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
                        ["Authorization"] = "Bearer " .. body["access_token"],
                        ["X-Addon-Header-A"] = "Value-A",
                        ["X-Addon-Header-B"] = "Value-b"
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
--- grep_error_log eval
qr/token validate successfully by \w+/
--- grep_error_log_out
token validate successfully by introspection



=== TEST 6: Access route with an invalid token, should work as expected too.
--- config
    location /t {
        content_by_lua_block {
            -- Access route using a fake access token.
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                    ["X-Addon-Header-A"] = "Value-A",
                    ["X-Addon-Header-B"] = "Value-b"
                }
             })

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- response_body
false
--- error_log
OIDC introspection failed: invalid token



=== TEST 7: Update route with fake Keycloak introspection endpoint and introspection addon headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:1980/log_request",
                                "introspection_addon_headers": ["X-Addon-Header-A", "X-Addon-Header-B"]
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



=== TEST 8: Check http headers from fake introspection endpoint.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. "fake access token",
                        ["X-Addon-Header-A"] = "Value-A",
                        ["X-Addon-Header-B"] = "Value-b"
                    }
                })
            ngx.status = res.status
        }
    }
--- error_code: 401
--- error_log
OIDC introspection failed: JSON decoding failed
--- grep_error_log eval
qr/x-addon-header-.{10}/
--- grep_error_log_out
x-addon-header-a: Value-A
x-addon-header-b: Value-b
