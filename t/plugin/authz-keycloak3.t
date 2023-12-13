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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: access_denied_redirect_uri works with request denied in token_endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "authz-keycloak": {
                                "token_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token",
                                "access_denied_redirect_uri": "http://127.0.0.1/test",
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
--- response_body
passed



=== TEST 2: hit
--- config
    location /t {
        content_by_lua_block {
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
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

                 ngx.status = res.status
                 ngx.header["Location"] = res.headers["Location"]
            end
        }
    }
--- error_code: 307
--- response_headers
Location: http://127.0.0.1/test



=== TEST 3: data encryption for client_secret
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
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
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["authz-keycloak"].client_secret)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["authz-keycloak"].client_secret)
        }
    }
--- response_body
d1ec69e9-55d2-4109-a3ea-befa071579d5
Fz1juZEEvh9PPXOmWFdMMJkREt3ZSzEVWcUZPxNP6achk3fosEvn37oN0qH4YgKB
