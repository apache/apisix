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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup all-in-one test
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/kafka",
                    data = [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:9092": 1
                            },
                            "type": "none",
                            "scheme": "kafka"
                        },
                        "uri": "/kafka"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/kafka-tlsv",
                    data = [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:9093": 1
                            },
                            "type": "none",
                            "scheme": "kafka",
                            "tls": {
                                "verify": true
                            }
                        },
                        "uri": "/kafka-tlsv"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/kafka-tls",
                    data = [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:9093": 1
                            },
                            "type": "none",
                            "scheme": "kafka",
                            "tls": {
                                "verify": false
                            }
                        },
                        "uri": "/kafka-tls"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/kafka-sasl",
                    data = [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:9094": 1
                            },
                            "type": "none",
                            "scheme": "kafka"
                        },
                        "uri": "/kafka-sasl",
                        "plugins": {
                            "kafka-proxy": {
                                "enable_sasl": true,
                                "sasl": {
                                    "username": "testuser",
                                    "password": "testpwd"
                                }
                            }
                        }
                    }]],
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n"x4



=== TEST 2: hit route (with HTTP request)
--- request
GET /kafka
--- error_code: 400
--- error_log
failed to initialize pub-sub module, err: bad "upgrade" request header: nil



=== TEST 3: hit route (normal Kafka)
--- config
    location /t {
        content_by_lua_block {
            local protoc = require("protoc")
            local pb = require("pb")
            protoc.reload()
            pb.option("int64_as_string")
            local pubsub_protoc = protoc.new()
            pubsub_protoc:addpath("apisix")
            local ok, err = pcall(pubsub_protoc.loadfile, pubsub_protoc, "pubsub.proto")
            if not ok then
                ngx.say("failed to load protocol: " .. err)
                return
            end

            local client = require "resty.websocket.client"
            local ws, err = client:new()
            local ok, err = ws:connect("ws://127.0.0.1:1984/kafka")
            if not ok then
                ngx.say("failed to connect: " .. err)
                return
            end

            local data = {
                {
                    sequence = 0,
                    cmd_kafka_list_offset = {
                        topic = "not-exist",
                        partition = 0,
                        timestamp = -1,
                    },
                },
                {
                    sequence = 1,
                    cmd_kafka_fetch = {
                        topic = "not-exist",
                        partition = 0,
                        offset = 0,
                    },
                },
                {
                    sequence = 2,
                    cmd_kafka_list_offset = {
                        topic = "test-consumer",
                        partition = 0,
                        timestamp = -2,
                    },
                },
                {
                    sequence = 3,
                    cmd_kafka_list_offset = {
                        topic = "test-consumer",
                        partition = 0,
                        timestamp = -1,
                    },
                },
                {
                    sequence = 4,
                    cmd_kafka_fetch = {
                        topic = "test-consumer",
                        partition = 0,
                        offset = 14,
                    },
                }
            }

            for i = 1, #data do
                local _, err = ws:send_binary(pb.encode("PubSubReq", data[i]))
                local raw_data, raw_type, err = ws:recv_frame()
                if not raw_data then
                    ngx.say("failed to receive the frame: ", err)
                    return
                end
                local data, err = pb.decode("PubSubResp", raw_data)
                if not data then
                    ngx.say("failed to decode the frame: ", err)
                    return
                end

                if data.error_resp then
                    ngx.say(data.sequence..data.error_resp.message)
                end
                if data.kafka_list_offset_resp then
                    ngx.say(data.sequence.."offset: "..data.kafka_list_offset_resp.offset)
                end
                if data.kafka_fetch_resp then
                    ngx.say(data.sequence.."offset: "..data.kafka_fetch_resp.messages[1].offset..
                        " msg: "..data.kafka_fetch_resp.messages[1].value)
                end
            end

            ws:send_close()
        }
    }
--- response_body
0failed to list offset, topic: not-exist, partition: 0, err: not found topic
1failed to fetch message, topic: not-exist, partition: 0, err: not found topic
2offset: 0
3offset: 30
4offset: 14 msg: testmsg15



=== TEST 4: hit route (TLS with ssl verify Kafka)
--- config
    location /t {
        content_by_lua_block {
            local protoc = require("protoc")
            local pb = require("pb")
            protoc.reload()
            pb.option("int64_as_string")
            local pubsub_protoc = protoc.new()
            pubsub_protoc:addpath("apisix")
            local ok, err = pcall(pubsub_protoc.loadfile, pubsub_protoc, "pubsub.proto")
            if not ok then
                ngx.say("failed to load protocol: " .. err)
                return
            end

            local client = require "resty.websocket.client"
            local ws, err = client:new()
            local ok, err = ws:connect("ws://127.0.0.1:1984/kafka-tlsv")
            if not ok then
                ngx.say("failed to connect: " .. err)
                return
            end

            local data = {
                {
                    sequence = 0,
                    cmd_kafka_list_offset = {
                        topic = "test-consumer",
                        partition = 0,
                        timestamp = -2,
                    },
                }
            }

            for i = 1, #data do
                local _, err = ws:send_binary(pb.encode("PubSubReq", data[i]))
                local raw_data, raw_type, err = ws:recv_frame()
                if not raw_data then
                    ngx.say("failed to receive the frame: ", err)
                    return
                end
                local data, err = pb.decode("PubSubResp", raw_data)
                if not data then
                    ngx.say("failed to decode the frame: ", err)
                    return
                end

                if data.kafka_list_offset_resp then
                    ngx.say(data.sequence.."offset: "..data.kafka_list_offset_resp.offset)
                end
            end

            ws:send_close()
        }
    }
--- response_body
0failed to list offset, topic: not-exist, partition: 0, err: not found topic
1failed to fetch message, topic: not-exist, partition: 0, err: not found topic
2offset: 0
3offset: 30
4offset: 14 msg: testmsg15
