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
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: configure integer and string proto references
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local content = [[
                syntax = "proto3";
                package helloworld;
                service Greeter {
                    rpc SayHello (HelloRequest) returns (HelloReply) {}
                }
                message HelloRequest { string name = 1; }
                message HelloReply { string message = 1; }
            ]]
            local code, body = t('/apisix/admin/protos/1', ngx.HTTP_PUT,
                                 core.json.encode({content = content}))
            assert(code < 300, body)

            for _, id in ipairs({1, "1"}) do
                local name = type(id)
                code, body = t('/apisix/admin/routes/proto-id-' .. name, ngx.HTTP_PUT,
                    core.json.encode({
                        uri = "/proto-id-" .. name,
                        plugins = {
                            ["grpc-transcode"] = {
                                proto_id = id,
                                service = "helloworld.Greeter",
                                method = "SayHello",
                            }
                        },
                        upstream = {
                            scheme = "grpc",
                            type = "roundrobin",
                            nodes = {["127.0.0.1:10051"] = 1},
                        }
                    }))
                assert(code < 300, body)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: integer proto_id transcodes a request
--- request
POST /proto-id-number
{"name":"world"}
--- more_headers
Content-Type: application/json
--- response_body eval
qr/"message":"Hello world"/



=== TEST 3: string proto_id remains compatible
--- request
POST /proto-id-string
{"name":"world"}
--- more_headers
Content-Type: application/json
--- response_body eval
qr/"message":"Hello world"/



=== TEST 4: ID normalization preserves missing IDs and distinct string IDs
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.grpc-transcode.proto")
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local content = [[
                syntax = "proto3";
                package leadingzero;
                message Reply { string value = 1; }
            ]]
            local _, version = proto.protos()
            local code, body = t('/apisix/admin/protos/01', ngx.HTTP_PUT,
                                 core.json.encode({content = content}))
            assert(code < 300, body)
            local current
            for _ = 1, 100 do
                _, current = proto.protos()
                if current ~= version then
                    break
                end
                ngx.sleep(0.05)
            end
            assert(current ~= version, "proto creation was not observed")

            local integer = assert(proto.fetch(1))
            assert(proto.fetch("1") == integer)
            local leading_zero = assert(proto.fetch("01"))
            assert(leading_zero ~= integer)
            for _, id in ipairs({987654321, "987654321"}) do
                local value, err = proto.fetch(id)
                assert(value == nil)
                assert(err == "failed to find proto by id: 987654321", err)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: proto updates invalidate both integer and string references
--- config
    location /t {
        content_by_lua_block {
            local proto = require("apisix.plugins.grpc-transcode.proto")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local pb = require("pb")
            local before = assert(proto.fetch(1))
            assert(proto.fetch("1") == before)
            local _, version = proto.protos()
            local content = [[
                syntax = "proto3";
                package helloworld;
                service Greeter {
                    rpc SayHello (HelloRequest) returns (HelloReply) {}
                }
                message HelloRequest { string name = 1; }
                message HelloReply { string updated_message = 1; }
            ]]
            local code, body = t('/apisix/admin/protos/1', ngx.HTTP_PUT,
                                 core.json.encode({content = content}))
            assert(code < 300, body)
            local current
            for _ = 1, 100 do
                _, current = proto.protos()
                if current ~= version then
                    break
                end
                ngx.sleep(0.05)
            end
            assert(current ~= version, "proto update was not observed")
            local after = assert(proto.fetch(1))
            assert(after ~= before)
            assert(proto.fetch("1") == after)
            local old_state = pb.state(after.pb_state)
            local decoded = pb.decode("helloworld.HelloReply", "\10\5hello")
            pb.state(old_state)
            ngx.say(decoded.updated_message)
        }
    }
--- request
GET /t
--- response_body
hello



=== TEST 6: integer reference uses the updated response schema
--- request
POST /proto-id-number
{"name":"world"}
--- more_headers
Content-Type: application/json
--- response_body eval
qr/"updated_message":"Hello world"/



=== TEST 7: string reference uses the updated response schema
--- request
POST /proto-id-string
{"name":"world"}
--- more_headers
Content-Type: application/json
--- response_body eval
qr/"updated_message":"Hello world"/
