# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: enable jwt-auth on the route /hello
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
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



=== TEST 2: create a consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack"
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



=== TEST 3: create a credential with jwt-auth plugin enabled for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "jwt-auth": {"key": "user-key", "secret": "my-secret-key"}
                     }
                }]],
                [[{
                    "value":{
                        "id":"34010989-ce4e-4d61-9493-b54cca8edb31",
                        "plugins":{
                            "jwt-auth": {"key": "user-key", "secret": "kK0lkbzXrE7aiTiyK/Z0Sw=="}
                        }
                    },
                    "key":"/apisix/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: access with invalid JWT token
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwiZXhwIjoxNjk1MTM4NjM1fQ.Au2liSZ8eQXUJR3SJESwNlIfqZdNyRyxIJK03L4dk_g
--- error_code: 401
--- response_body
{"message":"Invalid user key in JWT token"}



=== TEST 5: access with valid JWT token in header
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_body
hello world
