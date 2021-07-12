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
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: post proto + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message, res = t('/apisix/admin/proto',
                 ngx.HTTP_POST,
                 [[{
                        "content": "syntax = \"proto3\";
                            package proto;
                            message HelloRequest{
                            string name = 1;
                                }

                            message HelloResponse{
                            int32 code = 1;
                            string msg = 2;
                                }
                                // The greeting service definition.
                            service Hello {
                                    // Sends a greeting
                            rpc SayHi (HelloRequest) returns (HelloResponse){}
                                }"
                }]],
                [[
                    {
                        "node": {
                            "value": {
                                "create_time": 1625845753,
                                "update_time": 1625845753,
                                "content": "syntax = \"proto3\";\npackage proto;\nmessage HelloRequest{\n  string name = 1;\n    }\n\nmessage HelloResponse{\n  int32 code = 1;\n  string msg = 2;\n    }\n    // The greeting service definition.\nservice Hello {\n        // Sends a greeting\n  rpc SayHi (HelloRequest) returns (HelloResponse){}\n    }"
                            }
                        },
                        "action": "create"
                    }
                ]]
                )

            if code ~= 201 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/proto/" + 1)
            local res = assert(etcd.get('/proto/' .. id))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

            code, message = t('/apisix/admin/proto/' .. id,
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]
