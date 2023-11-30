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

=== TEST 1: minimal valid configuration w/o discovery
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                token_endpoint = "https://host.domain/realms/foo/protocol/openid-connect/token"
                            })
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



=== TEST 2: minimal valid configuration with discovery
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                discovery = "https://host.domain/realms/foo/.well-known/uma2-configuration"
                            })
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



=== TEST 3: minimal valid configuration w/o discovery when lazy_load_paths=true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                lazy_load_paths = true,
                                token_endpoint = "https://host.domain/realms/foo/protocol/openid-connect/token",
                                resource_registration_endpoint = "https://host.domain/realms/foo/authz/protection/resource_set"
                            })
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



=== TEST 4: minimal valid configuration with discovery when lazy_load_paths=true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                lazy_load_paths = true,
                                discovery = "https://host.domain/realms/foo/.well-known/uma2-configuration"
                            })
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



=== TEST 5: full schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                discovery = "https://host.domain/realms/foo/.well-known/uma2-configuration",
                                token_endpoint = "https://host.domain/realms/foo/protocol/openid-connect/token",
                                resource_registration_endpoint = "https://host.domain/realms/foo/authz/protection/resource_set",
                                client_id = "University",
                                client_secret = "secret",
                                grant_type = "urn:ietf:params:oauth:grant-type:uma-ticket",
                                policy_enforcement_mode = "ENFORCING",
                                permissions = {"res:customer#scopes:view"},
                                lazy_load_paths = false,
                                http_method_as_scope = false,
                                timeout = 1000,
                                ssl_verify = false,
                                cache_ttl_seconds = 1000,
                                keepalive = true,
                                keepalive_timeout = 10000,
                                keepalive_pool = 5,
                                access_token_expires_in = 300,
                                access_token_expires_leeway = 0,
                                refresh_token_expires_in = 3600,
                                refresh_token_expires_leeway = 0,
                                password_grant_token_generation_incoming_uri = "/api/token",
                            })
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



=== TEST 6: token_endpoint and discovery both missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({client_id = "foo"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
allOf 1 failed: object matches none of the required: ["discovery"] or ["token_endpoint"]
done



=== TEST 7: client_id missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({discovery = "https://host.domain/realms/foo/.well-known/uma2-configuration"})
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



=== TEST 8: resource_registration_endpoint and discovery both missing and lazy_load_paths is true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                token_endpoint = "https://host.domain/realms/foo/protocol/openid-connect/token",
                                lazy_load_paths = true
                            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
allOf 2 failed: object matches none of the required
done



=== TEST 9: Add https endpoint with ssl_verify true (default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
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



=== TEST 10: TEST with fake token and https endpoint
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            ngx.status = res.status

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
Error while sending authz request to https://127.0.0.1:8443/realms/University/protocol/openid-connect/token: 18
--- error_code: 503



=== TEST 11: Add https endpoint with ssl_verify false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource#delete"],
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000,
                                "ssl_verify": false
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
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



=== TEST 12: TEST for https based token verification with ssl_verify false
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
Request denied: HTTP 401 Unauthorized. Body: {"error":"HTTP 401 Unauthorized"}



=== TEST 13: set enforcement mode is "ENFORCING", lazy_load_paths and permissions use default values
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "policy_enforcement_mode": "ENFORCING",
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



=== TEST 14: test for permission is empty and enforcement mode is "ENFORCING".
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body
{"error":"access_denied","error_description":"not_authorized"}
--- no_error_log



=== TEST 15: set enforcement mode is "ENFORCING", lazy_load_paths and permissions use default values , access_denied_redirect_uri is "http://127.0.0.1/test"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "client_id": "course_management",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "policy_enforcement_mode": "ENFORCING",
                                "timeout": 3000,
                                "access_denied_redirect_uri": "http://127.0.0.1/test"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
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



=== TEST 16: test for permission is empty and enforcement mode is "ENFORCING" , access_denied_redirect_uri is "http://127.0.0.1/test".
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })
            if res.status >= 300 then
                ngx.status = res.status
                ngx.header["Location"] = res.headers["Location"]
            end
        }
    }
--- request
GET /t
--- response_headers
Location: http://127.0.0.1/test
--- error_code: 307



=== TEST 17: Add https endpoint with password_grant_token_generation_incoming_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource#view"],
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000,
                                "ssl_verify": false,
                                "password_grant_token_generation_incoming_uri": "/api/token"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api/token"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/token"
            local res, err = httpc:request_uri(uri, {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                },

                body =  ngx.encode_args({
                    username = "teacher@gmail.com",
                    password = "123456",
                }),
            })

            if res.status == 200 then
                local body = json_decode(res.body)
                local accessToken = body["access_token"]
                local refreshToken = body["refresh_token"]

                if accessToken and refreshToken then
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



=== TEST 18: no username or password
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource#view"],
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3000,
                                "ssl_verify": false,
                                "password_grant_token_generation_incoming_uri": "/api/token"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api/token"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/token"
            local headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded",
            }

            -- no username
            local res, err = httpc:request_uri(uri, {
                method = "POST",
                headers = headers,
                body =  ngx.encode_args({
                    password = "123456",
                }),
            })
            ngx.print(res.body)

            -- no password
            local res, err = httpc:request_uri(uri, {
                method = "POST",
                headers = headers,
                body =  ngx.encode_args({
                    username = "teacher@gmail.com",
                }),
            })
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
{"message":"username is missing."}
{"message":"password is missing."}
