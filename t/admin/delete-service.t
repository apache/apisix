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
no_root_location();

run_tests();

__DATA__

=== TEST 1: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        },
                        "key": "/apisix/services/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 2: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": 1,
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "service_id": 1,
                            "uri": "/index.html"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 3: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
                )
            ngx.print("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 400 message: {"error_msg":"can not delete this service directly, route [1] is still using it now"}
--- no_error_log
[error]



=== TEST 4: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 5: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]
