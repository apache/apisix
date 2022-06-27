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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set ssls(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local etcd = require("apisix.core.etcd")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "sni": "test.com"
                        },
                        "key": "/apisix/ssl/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/ssl/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

        }
    }
--- response_body
passed



=== TEST 2: put protos (id:1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/protos/1',
                 ngx.HTTP_PUT,
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
                        "action": "set"
                    }
                ]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say("[put proto] code: ", code, " message: ", message)
                return
            end

            ngx.say("[put proto] code: ", code, " message: ", message)
        }
    }
--- response_body
[put proto] code: 200 message: passed
