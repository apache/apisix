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
run_tests;

__DATA__

=== TEST 1: add plugin with view course permissions (using token endpoint)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource#view"],
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "authz-keycloak": {
                                    "token_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token",
                                    "permissions": ["course_resource#view"],
                                    "client_id": "course_management",
                                    "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                    "timeout": 3000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
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



=== TEST 2: Get access token for teacher and access view course route
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 3: invalid access token
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer wrong_token",
                    }
                })
            if res.status == 401 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
Invalid bearer token



=== TEST 4: add plugin with view course permissions (using discovery)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                "permissions": ["course_resource#view"],
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "authz-keycloak": {
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                    "permissions": ["course_resource#view"],
                                    "client_id": "course_management",
                                    "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                    "timeout": 3000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
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



=== TEST 5: Get access token for teacher and access view course route
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 6: invalid access token
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer wrong_token",
                    }
                })
            if res.status == 401 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
Invalid bearer token



=== TEST 7: add plugin for delete course route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource#delete"],
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "authz-keycloak": {
                                    "token_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token",
                                    "permissions": ["course_resource#delete"],
                                    "client_id": "course_management",
                                    "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                    "timeout": 3000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
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



=== TEST 8: Get access token for student and delete course
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=student@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 403 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
{"error":"access_denied","error_description":"not_authorized"}



=== TEST 9: add plugin with lazy_load_paths and http_method_as_scope
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "lazy_load_paths": true,
                                "http_method_as_scope": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/course/foo"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "authz-keycloak": {
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                    "client_id": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "lazy_load_paths": true,
                                    "http_method_as_scope": true
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/course/foo"
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



=== TEST 10: Get access token for teacher and access view course route.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 11: Get access token for student and access view course route.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=student@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 12: Get access token for teacher and delete course.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "DELETE",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 13: Get access token for student and try to delete course. Should fail.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=student@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "DELETE",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 403 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
{"error":"access_denied","error_description":"not_authorized"}



=== TEST 14: add plugin with lazy_load_paths and http_method_as_scope (using audience)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                "audience": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "lazy_load_paths": true,
                                "http_method_as_scope": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/course/foo"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "authz-keycloak": {
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/uma2-configuration",
                                    "audience": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "lazy_load_paths": true,
                                    "http_method_as_scope": true
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/course/foo"
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



=== TEST 15: Get access token for teacher and access view course route.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 16: Get access token for student and access view course route.
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=student@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]


                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/course/foo"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. accessToken,
                    }
                 })

                if res.status == 200 then
                    ngx.say(true)
                else
                    ngx.say(false)
                end
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]
