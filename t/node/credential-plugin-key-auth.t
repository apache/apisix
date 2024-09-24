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


=== TEST 1: enable key-auth on the route /hello
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



=== TEST 3: create a credential with key-auth plugin enabled for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {"key": "p7a3k6r4t9"}
                     }
                }]],
                [[{
                    "value":{
                        "id":"34010989-ce4e-4d61-9493-b54cca8edb31",
                        "plugins":{
                            "key-auth": {"key": "fsFPtg7BtXMXkvSnS9e1zw=="}
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



=== TEST 4: request with an invalid key: should be not OK
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 401
--- response_body
{"message":"Invalid API key in request"}



=== TEST 5: request with the valid key: should be OK
--- request
GET /hello
--- more_headers
apikey: p7a3k6r4t9
--- response_body
hello world
