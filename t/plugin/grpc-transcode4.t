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
# ensure that the JSON module of Perl is installed in your test environment. 
# If it is not installed, sudo cpanm JSON.
use JSON;

no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
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
                    package user;
                    service UserService {
                        rpc GetUserInfo(UserRequest) returns (UserResponse) {}
                     }

                    enum Gender {
                        GENDER_UNSPECIFIED = 0;
                        GENDER_MALE = 1;
                        GENDER_FEMALE = 2;
                    }
                    message Job {
                        string items = 1;
                    }                                        
                    message UserRequest {
                        string name = 1;
                        int32 age = 2;
                    }

                    message UserResponse {
                        Gender gender = 1;
                        repeated string items = 2;
                        string message = 3;
                        Job job = 4;
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
                            "service": "user.UserService",
                            "method": "GetUserInfo"
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
{"name":"testUser0","age":0}
--- more_headers
Content-Type: application/json
--- response_body_json
{"gender":"GENDER_MALE","message":"You are an experienced user!","items":["Senior member","Exclusive service"],"job":{"items":"Intern engineer"}}


=== TEST 3: hit route
--- request
POST /grpctest
{"name":"testUser1","age":1}
--- more_headers
Content-Type: application/json
--- response_body_json
{"gender":"GENDER_FEMALE","message":"Welcome new users!","job":{"items":"junior engineer"},"items":[]}


=== TEST 4: hit route
--- request
POST /grpctest
{"name":"testUser2","age":2}
--- more_headers
Content-Type: application/json
--- response_body_json
{"items":[],"message":"You are an experienced user!","job":{"items":"senior engineer"},"gender":"GENDER_UNSPECIFIED"}


=== TEST 5: hit route
--- request
POST /grpctest
{"name":"testUserDefault","age":100}
--- more_headers
Content-Type: application/json
--- response_body_json
{"gender":"GENDER_UNSPECIFIED","items":[],"message":""}
