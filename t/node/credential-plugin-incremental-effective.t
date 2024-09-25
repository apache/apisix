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

=== TEST 1: test continuous watch etcd changes without APISIX reload
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- enable key-auth on /hello
            t('/apisix/admin/routes/1',
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
            ngx.sleep(0.2) -- On some machines, changes may not be instantly watched, so sleep makes the test more robust.

            -- request /hello without key-auth should response status 401
            local code, body = t('/hello', ngx.HTTP_GET)
            assert(code == 401)

            -- add a consumer jack
            t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack"
                }]],
                [[{
                    "key": "/apisix/consumers/jack",
                    "value":
                    {
                        "username":"jack"
                    }
                }]]
            )

            -- create first credential for consumer jack
            t('/apisix/admin/consumers/jack/credentials/the-first-one',
                ngx.HTTP_PUT,
                [[{
                     "plugins":{"key-auth":{"key":"p7a3k6r4t9"}}
                }]],
                [[{
                    "value":{
                        "id":"the-first-one",
                        "plugins":{"key-auth":{"key":"p7a3k6r4t9"}}
                    },
                    "key":"/apisix/consumers/jack/credentials/the-first-one"
                }]]
            )
            ngx.sleep(0.2)

            -- request /hello with credential a
            local headers = {}
            headers["apikey"] = "p7a3k6r4t9"
            code, body = t('/hello', ngx.HTTP_GET, "", nil, headers)
            assert(code == 200)

            -- create second credential for consumer jack
            t('/apisix/admin/consumers/jack/credentials/the-second-one',
                ngx.HTTP_PUT,
                [[{
                     "plugins":{"key-auth":{"key":"v8p3q6r7t9"}}
                }]],
                [[{
                    "value":{
                        "id":"the-second-one",
                        "plugins":{"key-auth":{"key":"v8p3q6r7t9"}}
                    },
                    "key":"/apisix/consumers/jack/credentials/the-second-one"
                }]]
            )
            ngx.sleep(0.2)

            -- request /hello with credential b
            headers["apikey"] = "v8p3q6r7t9"
            code, body = t('/hello', ngx.HTTP_GET, "", nil, headers)
            assert(code == 200)

            -- delete the first credential
            code, body = t('/apisix/admin/consumers/jack/credentials/the-first-one', ngx.HTTP_DELETE)
            assert(code == 200)
            ngx.sleep(0.2)

            -- request /hello with credential a
            headers["apikey"] = "p7a3k6r4t9"
            code, body = t('/hello', ngx.HTTP_GET, "", nil, headers)
            assert(code == 401)
        }
    }
--- request
GET /t
