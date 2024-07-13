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
BEGIN {
    $ENV{VAULT_TOKEN} = "root";
    $ENV{CLIENT_SECRET} = "d1ec69e9-55d2-4109-a3ea-befa071579d5";
}

use t::APISIX 'no_plan';

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: using http should not give security warning
--- config
    location /t {
        content_by_lua_block {
    local check = {"discovery", "token_endpoint", "resource_registration_endpoint", "access_denied_redirect_uri"}
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                discovery = "http://host.domain/realms/foo/protocol/openid-connect/token",
                                token_endpoint = "http://token_endpoint.domain",
                                resource_registration_endpoint = "http://resource_registration_endpoint.domain",
                                access_denied_redirect_uri = "http://access_denied_redirect_uri.domain"
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
--- error_log
Using authz-keycloak discovery with no TLS is a security risk
Using authz-keycloak token_endpoint with no TLS is a security risk
Using authz-keycloak resource_registration_endpoint with no TLS is a security 
Using authz-keycloak access_denied_redirect_uri with no TLS is a security risk



=== TEST 2: using https should not give security warning
--- config
    location /t {
        content_by_lua_block {
    local check = {"discovery", "token_endpoint", "resource_registration_endpoint", "access_denied_redirect_uri"}
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                discovery = "https://host.domain/realms/foo/protocol/openid-connect/token",
                                token_endpoint = "https://token_endpoint.domain",
                                resource_registration_endpoint = "https://resource_registration_endpoint.domain",
                                access_denied_redirect_uri = "https://access_denied_redirect_uri.domain"
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
--- no_error_log
Using authz-keycloak discovery with no TLS is a security risk
Using authz-keycloak token_endpoint with no TLS is a security risk
Using authz-keycloak resource_registration_endpoint with no TLS is a security 
Using authz-keycloak access_denied_redirect_uri with no TLS is a security risk



=== TEST 3: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5
--- response_body
Success! Data written to: kv/apisix/foo



=== TEST 4: set client_secret as a reference to secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "root"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                                "permissions": ["course_resource"],
                                "client_id": "course_management",
                                "client_secret": "$secret://vault/test1/foo/client_secret",
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
                return ngx.say(body)
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
                    username = "teacher@gmail.com",
                    password = "123456",
                }),
            })
            if res.status == 200 then
                ngx.print("success\n")
            end
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 5: set client_secret as a reference to env variable
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
                                "permissions": ["course_resource"],
                                "client_id": "course_management",
                                "client_secret": "$env://CLIENT_SECRET",
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
                return
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
                    username = "teacher@gmail.com",
                    password = "123456",
                }),
            })
            if res.status == 200 then
                ngx.print("success\n")
            end
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 6: set invalid client_secret as a reference to env variable
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
                                "permissions": ["course_resource"],
                                "client_id": "course_management",
                                "client_secret": "$env://INVALID_CLIENT_SECRET",
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
                return
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
                    username = "teacher@gmail.com",
                    password = "123456",
                }),
            })
            if res.status == 200 then
                ngx.print("success\n")
            end
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/Invalid client secret/
--- grep_error_log_out
Invalid client secret
Invalid client secret
