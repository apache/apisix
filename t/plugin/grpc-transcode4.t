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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: empty repeated fields are decoded as arrays, maps stay objects
--- config
    location /t {
        content_by_lua_block {
            local grpc_proto = require("apisix.plugins.grpc-transcode.proto")
            local core = require("apisix.core")
            local pb = require("pb")

            local compiled = assert(grpc_proto.compile_proto([[
                syntax = "proto3";
                package t;
                message Inner {
                    repeated string tags = 1;
                }
                message Reply {
                    string msg = 1;
                    repeated string items = 2;
                    map<string, Inner> members = 3;
                    Inner inner = 4;
                    repeated Inner list = 5;
                }
            ]]))

            local old_state = pb.state(compiled.pb_state)
            local bin = pb.encode("t.Reply", {
                msg = "hi",
                members = {alice = {}},
                inner = {},
                list = {{}},
            })
            local decoded = pb.decode("t.Reply", bin)
            pb.state(old_state)

            ngx.say("items: ", core.json.encode(decoded.items))
            ngx.say("members: ", core.json.encode(decoded.members))
            ngx.say("nested in map: ", core.json.encode(decoded.members.alice.tags))
            ngx.say("nested in message: ", core.json.encode(decoded.inner.tags))
            ngx.say("nested in repeated: ", core.json.encode(decoded.list[1].tags))
        }
    }
--- response_body
items: []
members: {"alice":{"tags":[]}}
nested in map: []
nested in message: []
nested in repeated: []



=== TEST 2: non-empty repeated fields are unaffected
--- config
    location /t {
        content_by_lua_block {
            local grpc_proto = require("apisix.plugins.grpc-transcode.proto")
            local core = require("apisix.core")
            local pb = require("pb")

            local compiled = assert(grpc_proto.compile_proto([[
                syntax = "proto3";
                package t;
                message Reply {
                    repeated string items = 1;
                }
            ]]))

            local old_state = pb.state(compiled.pb_state)
            local bin = pb.encode("t.Reply", {items = {"a", "b"}})
            local decoded = pb.decode("t.Reply", bin)
            pb.state(old_state)

            ngx.say(core.json.encode(decoded.items))
        }
    }
--- response_body
["a","b"]



=== TEST 3: also works for protos loaded from a binary descriptor set
--- config
    location /t {
        content_by_lua_block {
            local grpc_proto = require("apisix.plugins.grpc-transcode.proto")
            local core = require("apisix.core")
            local protoc = require("protoc")
            local pb = require("pb")

            -- build a FileDescriptorSet, the same format the Admin API accepts
            protoc.reload()
            local parsed = protoc.new():parse([[
                syntax = "proto3";
                package t;
                message Reply {
                    string msg = 1;
                    repeated string items = 2;
                }
            ]])
            local descriptor_set = pb.encode("google.protobuf.FileDescriptorSet",
                                             {file = {parsed}})

            local compiled = assert(grpc_proto.compile_proto(
                                        ngx.encode_base64(descriptor_set)))

            local old_state = pb.state(compiled.pb_state)
            local decoded = pb.decode("t.Reply", pb.encode("t.Reply", {msg = "hi"}))
            pb.state(old_state)

            ngx.say(core.json.encode(decoded.items))
        }
    }
--- response_body
[]
