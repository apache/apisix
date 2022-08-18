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
          local http = require "resty.http"
          local t = require("lib.test_admin").test
          local code, body = t('/apisix/admin/protos/1',
                ngx.HTTP_PUT,
                [[{
                   "content" : "syntax = \"proto3\";
                    package helloworld;
                    service Greeter {
                         rpc SayMultipleHello(MultipleHelloRequest) returns (MultipleHelloReply) {}
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

                      message MultipleHelloRequest {
                          string name = 1;
                          repeated string items = 2;
                          repeated Gender genders = 3;
                          repeated Person persons = 4;
                    }

                    message MultipleHelloReply{
                          string message = 1;
                    }"
                }]]
              )

             if code >= 300 then
                 ngx.say(body)
                 return
              end

             local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                   "methods": ["POST"],
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "SayMultipleHello"
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
                ngx.say(body)
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: hit route
--- request
POST /grpctest
{"name":"world","persons":[{"name":"Joe","age":1},{"name":"Jake","age":2}]}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"Hello world, name: Joe, age: 1, name: Jake, age: 2"}
