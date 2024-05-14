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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: add consumer with basic-auth and key-auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        },
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
                        }
                    }
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



=== TEST 2: verify multi auth plugin (in header) with hiding credentials
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "key-auth": {
                                        "query": "apikey",
                                        "header": "authorization"
                                    }
                                },
                                {
                                    "jwt-auth": {
                                        "cookie": "jwt",
                                        "query": "jwt",
                                        "header": "authorization"
                                    }
                                }
                            ],
                            "hide_credentials": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /echo
--- more_headers
Authorization: auth-one
--- response_headers
!Authorization



=== TEST 3: verify key auth with same header with hiding credentials
--- request
GET /echo
--- more_headers
apikey: auth-one
--- response_headers
!Authorization



=== TEST 4: verify jwt-auth with same header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=user-key',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            -- verify JWT token
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers={authorization=sign}})

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_headers
!Authorization
