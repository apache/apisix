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

=== TEST 1: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5
--- response_body
Success! Data written to: kv/apisix/foo



=== TEST 2: set client_secret as a reference to secret
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
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



=== TEST 3: set client_secret as a reference to environment variable
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
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
                return ngx.say(body)
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