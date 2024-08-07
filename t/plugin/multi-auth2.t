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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: setup consumers with basic-auth and key-auth plugins with hide_credentials true option
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                            {
                                url = "/apisix/admin/consumers",
                                data = [[{
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
                             }]],
                            },
                            {
                                url = "/apisix/admin/routes/1",
                                data = [[{
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
                             }]],
                            },
                            {
                                url = "/apisix/admin/routes/2",
                                data = [[{
                                     "plugins": {
                                         "public-api": {}
                                     },
                                     "uri": "/apisix/plugin/jwt/sign"
                              }]],
                            },
                            {
                                url = "/apisix/admin/consumers",
                                data = [[{
                                 "username": "jack",
                                 "plugins": {
                                     "jwt-auth": {
                                         "key": "user-key",
                                         "secret": "my-secret-key"
                                     }
                                 }
                             }]],
                            }
                        }

             for _, data in ipairs(data) do
                        local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                        ngx.say(body)
             end
        }
    }
--- response_body eval
"passed\n" x 4



=== TEST 2: sign / verify jwt-auth
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

            local code, _, res = t('/echo?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_args
!jwt



=== TEST 3: verify key auth with same Authorization header with hiding credentials
--- request
GET /echo
--- more_headers
Authorization: auth-one
--- response_headers
!Authorization



=== TEST 4: verify jwt-key (in header) with hiding credentials
--- request
GET /echo
--- more_headers
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs
--- response_headers
!Authorization
