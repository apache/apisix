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
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n"x1



=== TEST 2: hit route (with HTTP request)
--- request
GET /kafka
--- error_code: 400
--- error_log
failed to initialize pub-sub module, err: bad "upgrade" request header: nil



=== TEST 3: hit route (Kafka)
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/kafka")
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
                local data = test_pubsub:send_recv_ws_binary(data[i])
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
            test_pubsub:close_ws()
        }
    }
--- response_body
0failed to list offset, topic: not-exist, partition: 0, err: not found topic
1failed to fetch message, topic: not-exist, partition: 0, err: not found topic
2offset: 0
3offset: 30
4offset: 14 msg: testmsg15
