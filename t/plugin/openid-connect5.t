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

=== TEST 1: Call to route with locking session storage should not block subsequent requests with same session
--- config
    set $session_storage redis;
    set $session_redis_prefix                   sessions;
    set $session_redis_database                 0;
    set $session_redis_connect_timeout          1000; # (in milliseconds)
    set $session_redis_send_timeout             1000; # (in milliseconds)
    set $session_redis_read_timeout             1000; # (in milliseconds)
    set $session_redis_host                     127.0.0.1;
    set $session_redis_port                     6379;
    set $session_redis_ssl                      off;
    set $session_redis_ssl_verify               off;
    set $session_redis_uselocking               on;
    set $session_redis_spinlockwait             150;  # (in milliseconds)
    set $session_redis_maxlockwait              30;   # (in seconds)

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

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
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_header": true,
                                "set_refresh_token_header": true
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

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']

            -- Make the final call to protected route
            local function firstRequest()
               local httpc = http.new()
               httpc:request_uri(redirect_uri, {
                        method = "GET",
                        headers = {
                            ["Cookie"] = cookie_str
                        }
                    })
            end

            ngx.thread.spawn(firstRequest)

            -- Make second call to protected route which should not timeout due to blocked session
            local httpc = http.new()
            httpc:set_timeout(2000)

            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
            })

            if err then
                ngx.say("request error: ", err)
                return
            end

            ngx.say(res.body)
        }
    }
--- response_body_like
hello world
