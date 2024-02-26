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
                            lifetime = 100
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
                                        "lifetime": 100
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
            local target_number = tonumber(parts[2], 10) - 100
            -- ngx.say(target_number, current_time)
            -- It takes time to execute the request, and there may be delays. So subtract one second.
            if target_number == current_time or target_number -1 == current_time then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
