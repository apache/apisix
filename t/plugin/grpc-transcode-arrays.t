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

=== TEST 1: repeated field name scoped to its message
--- config
    location /t {
        content_by_lua_block {
            local response = require("apisix.plugins.grpc-transcode.response")
            local helpers = response._TEST

            local message_index = {
                [".demo.Company"] = {
                    fields = {
                        name = {label = 3, type = 9},
                    },
                },
                [".demo.InnerName"] = {
                    fields = {
                        part = {label = 1, type = 9},
                    },
                },
                [".demo.HelloRequest"] = {
                    fields = {
                        company = {label = 1, type = 11, type_name = ".demo.Company"},
                        name = {label = 1, type = 11, type_name = ".demo.InnerName"},
                    },
                }
            }

            local data = {
                company = { name = {"foo", "bar"} },
                name = { part = "ceo" },
            }

            helpers.set_default_array(data,
                message_index[".demo.HelloRequest"], message_index)

            local array_mt = require("apisix.core").json.array_mt

            if getmetatable(data.company.name) ~= array_mt then
                ngx.status = 500
                ngx.say("company.name isn't treated as an array")
                return
            end

            if getmetatable(data.name) == array_mt then
                ngx.status = 500
                ngx.say("nested message incorrectly converted to array")
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: map values keep object semantics while nested arrays are applied
--- config
    location /t {
        content_by_lua_block {
            local response = require("apisix.plugins.grpc-transcode.response")
            local helpers = response._TEST

            local member_descriptor = {
                fields = {
                    alias = {label = 3, type = 9},
                }
            }

            local map_entry_descriptor = {
                map_entry = true,
                fields = {
                    key = {label = 1, type = 9},
                    value = {label = 1, type = 11, type_name = ".demo.Member"},
                },
            }
            map_entry_descriptor.map_value_field = map_entry_descriptor.fields.value

            local team_descriptor = {
                fields = {
                    members = {
                        label = 3,
                        type = 11,
                        type_name = ".demo.Team.MemberEntry",
                        is_map = true,
                        map_entry_descriptor = map_entry_descriptor,
                    }
                }
            }

            local message_index = {
                [".demo.Member"] = member_descriptor,
                [".demo.Team.MemberEntry"] = map_entry_descriptor,
                [".demo.Team"] = team_descriptor,
            }

            local data = {
                members = {
                    alice = { alias = {"aa", "ab"} },
                    bob = { alias = {"ba"} },
                }
            }

            helpers.set_default_array(data, message_index[".demo.Team"], message_index)

            local array_mt = require("apisix.core").json.array_mt

            if getmetatable(data.members) == array_mt then
                ngx.status = 500
                ngx.say("map field should not become an array")
                return
            end

            if getmetatable(data.members.alice.alias) ~= array_mt then
                ngx.status = 500
                ngx.say("map values should still apply nested arrays")
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed
