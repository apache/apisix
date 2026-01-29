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

repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity, default realm
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "dc=example,dc=com",
                            "ldap_uri": "ldap://127.0.0.1:1389"
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
--- request
GET /t
--- response_body
passed



=== TEST 2: verify default realm
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: Basic realm="ldap"



=== TEST 3: set custom realm
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "dc=example,dc=com",
                            "ldap_uri": "ldap://127.0.0.1:1389",
                            "realm": "my-ldap-realm"
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
--- request
GET /t
--- response_body
passed



=== TEST 4: verify custom realm
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: Basic realm="my-ldap-realm"



=== TEST 5: ldap auth failure (missing header) returns realm
--- request
GET /hello
--- error_code: 401
--- response_headers
WWW-Authenticate: Basic realm="my-ldap-realm"



=== TEST 6: ldap auth failure (invalid credentials) returns realm
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "dc=example,dc=com",
                            "ldap_uri": "ldap://127.0.0.1:1389",
                            "realm": "my-ldap-realm"
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
--- request
GET /t
--- response_body
passed



=== TEST 7: verify ldap invalid credentials returns realm
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjp3cm9uZw==
--- error_code: 401
--- response_headers
WWW-Authenticate: Basic realm="my-ldap-realm"
--- error_log
ldap-auth failed
