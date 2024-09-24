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


=== TEST 1: enable key-auth on the route /echo
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
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
GET /t
--- response_body
passed



=== TEST 2: create consumer
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



=== TEST 3: create a credential with key-auth plugin enabled and 'custom_id' label for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {"key": "p7a3k6r4t9"}
                     },
                     "labels": {
                         "custom_id": "271fc4a264bb"
                     }
                }]],
                [[{
                    "value":{
                        "id":"34010989-ce4e-4d61-9493-b54cca8edb31",
                        "plugins":{
                            "key-auth": {"key": "p7a3k6r4t9"}
                        },
                        "labels": {
                            "custom_id": "271fc4a264bb"
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



=== TEST 4: request the route: 'x-consumer-username' and 'x-credential-identifier' is in response headers and 'x-consumer-custom-id' is not
--- request
GET /echo HTTP/1.1
--- more_headers
apikey: p7a3k6r4t9
--- response_headers
x-consumer-username: jack
x-credential-identifier: 34010989-ce4e-4d61-9493-b54cca8edb31
!x-consumer-custom-id



=== TEST 5: update the consumer add label "custom_id"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "labels": {
                        "custom_id": "495aec6a"
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



=== TEST 6: request the route: the value of 'x-consumer-custom-id' come from the consumer but not the credential or downstream
--- request
GET /echo HTTP/1.1
--- more_headers
apikey: p7a3k6r4t9
x-consumer-custom-id: 271fc4a264bb
--- response_headers
x-consumer-username: jack
x-credential-identifier: 34010989-ce4e-4d61-9493-b54cca8edb31
x-consumer-custom-id: 495aec6a



=== TEST 7: delete the credential
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31', ngx.HTTP_DELETE)

            assert(code == 200)
            ngx.status = code
        }
    }
--- request
GET /t
--- response_body



=== TEST 8: update the consumer to enable a key-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                 ngx.HTTP_PUT,
                 [[{
                    "username": "jack",
                    "plugins": {
                            "key-auth": {
                                "key": "p7a3k6r4t9"
                            }
                        }
                }]],
                [[{
                    "value": {
                        "username": "jack",
                        "plugins": {
                            "key-auth": {
                                "key": "p7a3k6r4t9"
                            }
                        }
                    },
                    "key": "/apisix/consumers/jack"
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



=== TEST 9: request the route with headers x-credential-identifier and x-consumer-custom-id: these headers will be removed
--- request
GET /echo HTTP/1.1
--- more_headers
apikey: p7a3k6r4t9
x-credential-identifier: 34010989-ce4e-4d61-9493-b54cca8edb31
x-consumer-custom-id: 271fc4a264bb
--- response_headers
x-consumer-username: jack
!x-credential-identifier
!x-consumer-custom-id
