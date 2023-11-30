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
});

run_tests;

__DATA__

=== TEST 1: set rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/protos/1',
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
                            "127.0.0.1:10051": 1
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
            local code, body = t('/apisix/admin/protos/2',
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
                            "127.0.0.1:10051": 1
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



=== TEST 6: set binary rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local content = t.read_file("t/grpc_server_example/proto.pb")
            local data = {content = ngx.encode_base64(content)}
            local code, body = t.test('/apisix/admin/protos/1',
                 ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.TestImport",
                            "method": "Run"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
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



=== TEST 7: hit route
--- request
POST /grpctest
{"body":"world","user":{"name":"Hello"}}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"body":"Hello world"}



=== TEST 8: service/method not found
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/service_not_found",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.TestImportx",
                            "method": "Run"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
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
                    "uri": "/method_not_found",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.TestImport",
                            "method": "Runx"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
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



=== TEST 9: hit route
--- request
POST /service_not_found
{"body":"world","user":{"name":"Hello"}}
--- more_headers
Content-Type: application/json
--- error_log
Undefined service method
--- error_code: 503



=== TEST 10: hit route
--- request
POST /method_not_found
{"body":"world","user":{"name":"Hello"}}
--- more_headers
Content-Type: application/json
--- error_log
Undefined service method
--- error_code: 503



=== TEST 11: set proto(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/protos/1',
                 ngx.HTTP_PUT,
                 [[{
                    "content" : "syntax = \"proto3\";
                      package helloworld;
                      service Greeter {
                          rpc SayHello (HelloRequest) returns (HelloReply) {}
                          rpc Plus (PlusRequest) returns (PlusReply) {}
                          rpc SayHelloAfterDelay (HelloRequest) returns (HelloReply) {}
                      }

                      message HelloRequest {
                          string name = 1;
                      }
                      message HelloReply {
                          string message = 1;
                         }
                      message PlusRequest {
                          int64 a = 1;
                          int64 b = 2;
                      }
                      message PlusReply {
                          int64 result = 1;
                      }"
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



=== TEST 12: work with logger plugin which on global rule and read response body (logger plugins store undecoded body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpc_plus",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus",
                            "pb_option":["int64_as_string", "enum_as_name"]
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "include_resp_body": true
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: hit route
--- request
GET /grpc_plus?a=1&b=2
--- response_body eval
qr/\{"result":3\}/
--- error_log eval
qr/request log: \{.*body":\"\\u0000\\u0000\\u0000\\u0000\\u0002\\b\\u0003"/



=== TEST 14: delete global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE
            )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed



=== TEST 15: work with logger plugin which on route and read response body (logger plugins store decoded body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpc_plus",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus",
                            "pb_option":["int64_as_string", "enum_as_name"]
                        },
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "include_resp_body": true
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
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



=== TEST 16: hit route
--- request
GET /grpc_plus?a=1&b=2
--- response_body eval
qr/\{"result":3\}/
--- error_log eval
qr/request log: \{.*body":\"\{\\"result\\":3}/



=== TEST 17: pb_option should be be set on the route level
--- extra_init_by_lua
    local pb = require("pb")
    local old_f = pb.option
    pb.option = function(o)
        if o ~= "int64_as_string" and o ~= "int64_as_number" then
            -- filter out options set by other components.
            -- we can still test some options like enum_as_name
            ngx.log(ngx.WARN, "set protobuf option: ", o)
        end
        return old_f(o)
    end
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
                          rpc Plus (PlusRequest) returns (PlusReply) {}
                      }

                      message PlusRequest {
                          int64 a = 1;
                          int64 b = 2;
                      }
                      message PlusReply {
                          int64 result = 1;
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
                    "methods": ["GET"],
                    "uri": "/grpc_plus2",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpc_plus",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus",
                            "pb_option":["int64_as_string", "enum_as_name"]
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.say(body)
                return
            end

            for i = 1, 3 do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                    (i == 2 and "/grpc_plus2" or "/grpc_plus") ..
                    "?a=1&b=2251799813685260"
                local httpc = http.new()
                local res = assert(httpc:request_uri(uri, {keepalive = false}))
                ngx.say(res.body)
            end
        }
    }
--- response_body
{"result":"#2251799813685261"}
{"result":2.2517998136853e+15}
{"result":"#2251799813685261"}
--- grep_error_log eval
qr/set protobuf option: \w+/
--- grep_error_log_out
set protobuf option: enum_as_name
set protobuf option: auto_default_values
set protobuf option: disable_hooks
set protobuf option: enum_as_name
set protobuf option: enum_as_name



=== TEST 18: pb_option should be be set on the route level, two route have the same options
--- extra_init_by_lua
    local pb = require("pb")
    local old_f = pb.option
    pb.option = function(o)
        if o ~= "int64_as_string" and o ~= "int64_as_number" then
            -- filter out options set by other components
            -- we can still test some options like enum_as_name
            ngx.log(ngx.WARN, "set protobuf option: ", o)
        end
        return old_f(o)
    end
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
                          rpc Plus (PlusRequest) returns (PlusReply) {}
                      }

                      message PlusRequest {
                          int64 a = 1;
                          int64 b = 2;
                      }
                      message PlusReply {
                          int64 result = 1;
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
                    "methods": ["GET"],
                    "uri": "/grpc_plus2",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpc_plus",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "Plus"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.say(body)
                return
            end

            for i = 1, 3 do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                    (i == 2 and "/grpc_plus2" or "/grpc_plus") ..
                    "?a=1&b=2251799813685260"
                local httpc = http.new()
                local res = assert(httpc:request_uri(uri, {keepalive = false}))
                ngx.say(res.body)
            end
        }
    }
--- response_body
{"result":2.2517998136853e+15}
{"result":2.2517998136853e+15}
{"result":2.2517998136853e+15}
--- grep_error_log eval
qr/set protobuf option: \w+/
--- grep_error_log_out
set protobuf option: auto_default_values
set protobuf option: disable_hooks
set protobuf option: enum_as_name
