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

# The introspection mock used below acts as a strict authorization server
# which follows RFC 6749 Section 2.3.1: the client MUST NOT use more than
# one authentication mechanism in each request. It rejects introspection
# requests that carry client credentials in both the Authorization header
# and the request body.
run_tests();

__DATA__

=== TEST 1: Set up route with default introspection_endpoint_auth_method (client_secret_basic)
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
                                "introspection_endpoint": "http://127.0.0.1:1984/introspection"
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



=== TEST 2: Client credentials must only be sent in the Authorization header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer fake-access-token",
                }
            })

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
    location = /introspection {
        content_by_lua_block {
            ngx.req.read_body()
            local args = ngx.req.get_post_args()
            local auth_header = ngx.var.http_authorization
            local has_body_credentials = args.client_id ~= nil
                                         or args.client_secret ~= nil

            ngx.header["Content-Type"] = "application/json"

            if auth_header and has_body_credentials then
                ngx.status = 401
                ngx.say([[{"error":"invalid_client","error_description":"more than one client authentication mechanism used"}]])
                return
            end

            if not auth_header and not has_body_credentials then
                ngx.status = 401
                ngx.say([[{"error":"invalid_client","error_description":"client authentication missing"}]])
                return
            end

            if args.token ~= "fake-access-token" then
                ngx.say([[{"active":false}]])
                return
            end

            ngx.say([[{"active":true}]])
        }
    }
--- response_body
hello world



=== TEST 3: Update route to use introspection_endpoint_auth_method client_secret_post
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
                                "introspection_endpoint": "http://127.0.0.1:1984/introspection"
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



=== TEST 4: client_secret_post still sends client credentials in the request body
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer fake-access-token",
                }
            })

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
    location = /introspection {
        content_by_lua_block {
            ngx.req.read_body()
            local args = ngx.req.get_post_args()
            local auth_header = ngx.var.http_authorization
            local has_body_credentials = args.client_id ~= nil
                                         or args.client_secret ~= nil

            ngx.header["Content-Type"] = "application/json"

            if auth_header and has_body_credentials then
                ngx.status = 401
                ngx.say([[{"error":"invalid_client","error_description":"more than one client authentication mechanism used"}]])
                return
            end

            if not auth_header and not has_body_credentials then
                ngx.status = 401
                ngx.say([[{"error":"invalid_client","error_description":"client authentication missing"}]])
                return
            end

            if args.token ~= "fake-access-token" then
                ngx.say([[{"active":false}]])
                return
            end

            ngx.say([[{"active":true}]])
        }
    }
--- response_body
hello world



=== TEST 5: Set up route with client_secret_basic and introspection addon headers
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
                                "introspection_endpoint_auth_method": "client_secret_basic",
                                "introspection_endpoint": "http://127.0.0.1:1984/introspection",
                                "introspection_addon_headers": ["X-Addon-Header-A"]
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



=== TEST 6: Addon headers are still forwarded while body credentials are stripped
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer fake-access-token",
                    ["X-Addon-Header-A"] = "Value-A",
                }
            })

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
    location = /introspection {
        content_by_lua_block {
            ngx.req.read_body()
            local args = ngx.req.get_post_args()
            local auth_header = ngx.var.http_authorization

            ngx.header["Content-Type"] = "application/json"

            if not auth_header or args.client_id or args.client_secret
               or ngx.var.http_x_addon_header_a ~= "Value-A" then
                ngx.status = 401
                ngx.say([[{"error":"invalid_client"}]])
                return
            end

            ngx.say([[{"active":true}]])
        }
    }
--- response_body
hello world
