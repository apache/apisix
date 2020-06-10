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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                   token_endpoint = "https://efactory-security-portal.salzburgresearch.at/",
                                   grant_type = "test grant type"
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
[error]


=== TEST 2: full schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({token_endpoint = "https://efactory-security-portal.salzburgresearch.at/",
                                                 permissions = "res:customer#scopes:view",
                                                 timeout = 3,
                                                 audience = "CAMPAIGN_CLIENT",
                                                 max_retry_count = 2,
                                                 response_mode = "decision",
                                                 grant_type = "urn:ietf:params:oauth:grant-type:uma-ticket"
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
[error]


=== TEST 3: grant_type missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({token_endpoint = "https://efactory-security-portal.salzburgresearch.at/",
                                                 permissions = "res:customer#scopes:view",
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
property "grant_type" is required
done
--- no_error_log
[error]


=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8090/auth/realms/CAMPAIGN_CLIENT/protocol/openid-connect/token",
                                "permissions": "res:campaign#scopes:view",
                                "audience": "CAMPAIGN_CLIENT",
                                "response_mode": "decision",
                                "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                "timeout": 3
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
                                    "token_endpoint": "http://127.0.0.1:8090/auth/realms/CAMPAIGN_CLIENT/protocol/openid-connect/token",
                                    "permissions": "res:campaign#scopes:view",
                                    "audience": "CAMPAIGN_CLIENT",
                                    "response_mode": "decision",
                                    "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                                    "timeout": 3
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



=== TEST 5: access with correct token
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ6SUxOWUMzaFp0LTI5emc2VVY2RWV6WGMxZEZyamxSLVIxNHJ2cHdsUmhBIn0.eyJleHAiOjIwMjM4MjY2NjAsImlhdCI6MTU5MTgyNjY2MCwianRpIjoiMjE0MzcwMGItYjlmNS00YWRjLWFkZDQtOTg2MzhlMjY0ZGE3IiwiaXNzIjoiaHR0cDovLzEyNy4wLjAuMTo4MDkwL2F1dGgvcmVhbG1zL0NBTVBBSUdOX0NMSUVOVCIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJmZjA3NmUxNi0wMzNiLTQ5MjMtYjVjNS05MGZkNDc3NDFlMDciLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJDQU1QQUlHTl9DTElFTlQiLCJzZXNzaW9uX3N0YXRlIjoiNDUzZTVkY2YtNzM4MC00NTI2LTlmYTYtYWMwY2ZjZWU4NWVmIiwiYWNyIjoiMSIsImFsbG93ZWQtb3JpZ2lucyI6WyIqIl0sInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJvZmZsaW5lX2FjY2VzcyIsInVtYV9hdXRob3JpemF0aW9uIiwiY3VzdG9tZXItYWR2ZXJ0aXNlciJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoicHJvZmlsZSBlbWFpbCIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwicHJlZmVycmVkX3VzZXJuYW1lIjoiYWR2ZXJ0aXNlcl91c2VyIn0.MU1cYsEroZ4Vv70UBuHNpcxyvolQ-yGsnDuoM-muuqHsDgonRMz-_xeoc_RNRNcecJBbziyISZwaPNFb6089eeSQuqHO0FOuKF0ALc_5RO4xhrQWx3bupwNmJ6NcmjKKELDc62zZ2qE-aVGC4qMQ3hlF02-nkwjleV9GLFaDONUpxwnvtQrwuZVzuyMfX4mBOjUhwcmIFGJn5I4Ju3cgNZjOoTz4SOoa7sw8QU7--MXjwe0YUdvX654SVLYlRs_87ybwzCKtj8RQ2HBzqLGjHcAQId3Jrhd18nV1iMznzRVwsWm0r7t6CqhUOODFvJ8qx6Ij6m2VIqPOv43iQrIv_w",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]




