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

=== TEST 1: enable key-auth plugin on /hello
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- basic-auth on route 1
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



=== TEST 3: create the first credential with the key-auth plugin enabled for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/the-first-one',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {"key": "p7a3k6r4t9"}
                     }
                }]],
                [[{
                    "value":{
                        "id":"the-first-one",
                        "plugins":{
                            "key-auth": {"key": "fsFPtg7BtXMXkvSnS9e1zw=="}
                        }
                    },
                    "key":"/apisix/consumers/jack/credentials/the-first-one"
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



=== TEST 4: create the second credential with the key-auth plugin enabled for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/the-second-one',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {"key": "v8p3q6r7t9"}
                     }
                }]],
                [[{
                    "value":{
                        "id":"the-second-one",
                        "plugins":{
                            "key-auth": {"key": "QwGua2GjZjOiq+Mj3Mef2g=="}
                        }
                    },
                    "key":"/apisix/consumers/jack/credentials/the-second-one"
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



=== TEST 5: request /hello with the key of the first credential: should be OK
--- request
GET /hello
--- more_headers
apikey: p7a3k6r4t9
--- response_body
hello world



=== TEST 6: request /hello with the key of second credential: should be OK
--- request
GET /hello
--- more_headers
apikey: v8p3q6r7t9
--- response_body
hello world



=== TEST 7: delete the first credential
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/the-first-one', ngx.HTTP_DELETE)

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 8: request /hello with the key of the first credential: should be not OK
--- request
GET /hello
--- more_headers
apikey: p7a3k6r4t9
--- error_code: 401



=== TEST 9: request /hello with the key of the second credential: should be OK
--- request
GET /hello
--- more_headers
apikey: v8p3q6r7t9
--- response_body
hello world



=== TEST 10: delete the second credential
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/the-second-one', ngx.HTTP_DELETE)

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 11: request /hello with the key of the second credential: should be not OK
--- request
GET /hello
--- more_headers
apikey: v8p3q6r7t9
--- error_code: 401
