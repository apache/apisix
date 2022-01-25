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

no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: set rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/proto/1',
                 ngx.HTTP_PUT,
                 [[{
                    "content" : "syntax = \"proto3\";
                      package helloworld;
                      service Greeter {
                          rpc SayHello (HelloRequest) returns (HelloReply) {}
                      }
                      enum Gender {
                        GENDER_UNKNOWN = 0;
                        GENDER_MALE = 1;
                        GENDER_FEMALE = 2;
                      }
                      message Person {
                          string name = 1;
                          int32 age = 2;
                      }
                      message HelloRequest {
                          string name = 1;
                          repeated string items = 2;
                          Gender gender = 3;
                          Person person = 4;
                      }
                      message HelloReply {
                          string message = 1;
                      }"
                   }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "SayHello"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:50051": 1
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
--- response_body
passed



=== TEST 2: hit route
--- request
POST /grpctest
{"name":"world","person":{"name":"Joe","age":1}}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"Hello world, name: Joe, age: 1"}



=== TEST 3: hit route, missing some fields
--- request
POST /grpctest
{"name":"world","person":{"name":"Joe"}}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"Hello world, name: Joe"}



=== TEST 4: set rule to check if each proto is separate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/proto/2',
                 ngx.HTTP_PUT,
                 [[{
                    "content" : "syntax = \"proto3\";
                      package helloworld;
                      service Greeter {
                          rpc SayHello (HelloRequest) returns (HelloReply) {}
                      }
                      // same message, different fields. use to pollute the type info
                      message HelloRequest {
                          string name = 1;
                          string person = 2;
                      }
                      message HelloReply {
                          string message = 1;
                      }"
                   }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/fail",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "2",
                            "service": "helloworld.Greeter",
                            "method": "SayHello"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:50051": 1
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
--- response_body
passed



=== TEST 5: hit route
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local uri = "http://127.0.0.1:" .. ngx.var.server_port
        local body = [[{"name":"world","person":{"name":"John"}}]]
        local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}

        local function access(path)
            local httpc = http.new()
            local res, err = httpc:request_uri(uri .. path, opt)
            if not res then
                ngx.say(err)
                return
            end
            if res.status > 300 then
                ngx.say(res.status)
            else
                ngx.say(res.body)
            end
        end

        access("/fail")
        access("/grpctest")
        access("/fail")
        access("/grpctest")
    }
}
--- response_body
400
{"message":"Hello world, name: John"}
400
{"message":"Hello world, name: John"}
--- error_log
failed to encode request data to protobuf
