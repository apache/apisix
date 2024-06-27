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
                            "127.0.0.1:10051": 1
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



=== TEST 3: set proto (id: 1, get error response from rpc)
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
                          rpc GetErrResp (HelloRequest) returns (HelloReply) {}
                      }
                      message HelloRequest {
                          string name = 1;
                          repeated string items = 2;
                      }
                      message HelloReply {
                          string message = 1;
                          repeated string items = 2;
                      }
                      message ErrorDetail {
                          int64 code = 1;
                          string message = 2;
                          string type = 3;
                      }"
                   }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET", "POST"],
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "GetErrResp"
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



=== TEST 4: hit route (error response in header)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, headers = t('/grpctest?name=world',
                ngx.HTTP_GET
            )

            ngx.status = code

            ngx.header['grpc-status'] = headers['grpc-status']
            ngx.header['grpc-message'] = headers['grpc-message']
            ngx.header['grpc-status-details-bin'] = headers['grpc-status-details-bin']

            body = json.encode(body)
            ngx.say(body)
        }
    }
--- response_headers
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
--- response_body_unlike eval
qr/error/
--- error_code: 503



=== TEST 5: set routes (id: 1, show error response in body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET", "POST"],
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "GetErrResp",
                            "show_status_in_body": true
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



=== TEST 6: hit route (show error status in body)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, headers = t('/grpctest?name=world',
                ngx.HTTP_GET
            )

            ngx.status = code

            ngx.header['grpc-status'] = headers['grpc-status']
            ngx.header['grpc-message'] = headers['grpc-message']
            ngx.header['grpc-status-details-bin'] = headers['grpc-status-details-bin']

            body = json.decode(body)
            body = json.encode(body)
            ngx.say(body)
        }
    }
--- response_headers
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
--- response_body
{"error":{"code":14,"details":[{"type_url":"type.googleapis.com/helloworld.ErrorDetail","value":"\b\u0001\u0012\u001cThe server is out of service\u001a\u0007service"}],"message":"Out of service"}}
--- error_code: 503



=== TEST 7: set routes (id: 1, show error details in body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET", "POST"],
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "GetErrResp",
                            "show_status_in_body": true,
                            "status_detail_type": "helloworld.ErrorDetail"
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



=== TEST 8: hit route (show error details in body)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, headers = t('/grpctest?name=world',
                ngx.HTTP_GET
            )

            ngx.status = code

            ngx.header['grpc-status'] = headers['grpc-status']
            ngx.header['grpc-message'] = headers['grpc-message']
            ngx.header['grpc-status-details-bin'] = headers['grpc-status-details-bin']

            body = json.decode(body)
            body = json.encode(body)
            ngx.say(body)
        }
    }
--- response_headers
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
--- response_body
{"error":{"code":14,"details":[{"code":1,"message":"The server is out of service","type":"service"}],"message":"Out of service"}}
--- error_code: 503



=== TEST 9: set routes (id: 1, show error details in body and wrong status_detail_type)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET", "POST"],
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "GetErrResp",
                            "show_status_in_body": true,
                            "status_detail_type": "helloworld.error"
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



=== TEST 10: hit route (show error details in body and wrong status_detail_type)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, headers = t('/grpctest?name=world',
                ngx.HTTP_GET
            )

            ngx.status = code

            ngx.header['grpc-status'] = headers['grpc-status']
            ngx.header['grpc-message'] = headers['grpc-message']
            ngx.header['grpc-status-details-bin'] = headers['grpc-status-details-bin']

            ngx.say(body)
        }
    }
--- response_headers
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
--- response_body
failed to call pb.decode to decode details in grpc-status-details-bin
--- error_log
transform response error: failed to call pb.decode to decode details in grpc-status-details-bin, err:
--- error_code: 503



=== TEST 11: set binary rule for EchoStruct
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local content = t.read_file("t/grpc_server_example/echo.pb")
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
                            "service": "echo.Echo",
                            "method": "EchoStruct"
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



=== TEST 12: hit route to test EchoStruct
--- config
location /t {
    content_by_lua_block {
        local core = require "apisix.core"
        local http = require "resty.http"
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/grpctest"
        local body = [[{"data":{"fields":{"foo":{"string_value":"xxx"},"bar":{"number_value":666}}}}]]
        local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}, keepalive = false}
        local httpc = http.new()
        local res, err = httpc:request_uri(uri, opt)
        if not res then
            ngx.log(ngx.ERR, err)
            return ngx.exit(500)
        end
        if res.status > 300 then
            return ngx.exit(res.status)
        else
            local req = core.json.decode(body)
            local rsp = core.json.decode(res.body)
            for k, v in pairs(req.data.fields) do
                if rsp.data.fields[k] == nil then
                    ngx.log(ngx.ERR, "rsp missing field=", k, ", rsp: ", res.body)
                else
                    for k1, v1 in pairs(v) do
                        if v1 ~= rsp.data.fields[k][k1] then
                            ngx.log(ngx.ERR, "rsp mismatch: k=", k1,
                                ", req=", v1, ", rsp=", rsp.data.fields[k][k1])
                        end
                    end
                end
            end
        end
    }
}



=== TEST 13: bugfix - filter out illegal INT(string) formats
--- config
location /t {
    content_by_lua_block {
        local pb = require "pb"
        local pb_encode = pb.encode
        local protoc = require "protoc"
        local pcall = pcall

        assert(protoc:load [[
        syntax = "proto3";
        message IntStringPatterns {
          repeated int64 values = 1;
        }]])

        local supported = {
            values = {
                1, 2, -3, "#123", "0xabF", "#-0x123abcdef", "-#0x123abcdef", "#0x123abc", "123",
            },
        }

        local unsupported = {
            values = {
                "#a", "+aaa", "#aaaaa", "#-aa",
            },
        }

        --pb.option "int64_as_string"
        --pb.option "int64_as_hexstring"
        pb_encode("IntStringPatterns", supported)
        local status, err = pcall(pb_encode, "IntStringPatterns", unsupported)
        if not status then
            ngx.say(err)
        end
    }
}
--- response_body
bad argument #2 to '?' (number/'#number' expected for field 'values', got string)
