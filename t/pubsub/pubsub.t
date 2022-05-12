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

=== TEST 1: setup route by serverless
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/pubsub",
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "access",
                                functions =  {
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        local pubsub, err = core.pubsub.new()
                                        if not pubsub then
                                            core.log.error("failed to initialize pub-sub module, err: ", err)
                                            core.response.exit(400)
                                            return
                                        end
                                        pubsub:on("cmd_kafka_list_offset", function (params)
                                            return nil, "test"
                                        end)
                                        pubsub:wait()
                                        ngx.exit(0)
                                    end]],
                                }
                            }
                        },
                        uri = "/pubsub"
                    },
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body
201passed



=== TEST 2: hit route (with HTTP request)
--- request
GET /pubsub
--- error_code: 400
--- error_log
failed to initialize pub-sub module, err: bad "upgrade" request header: nil



=== TEST 3: connect websocket service
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            local data = test_pubsub:send_recv_ws({
                sequence = 0,
                cmd_kafka_list_offset = {
                    topic = "test",
                    partition = 0,
                    timestamp = -2,
                },
            })
            if data and data.error_resp then
                ngx.say("ret: ", data.error_resp.message)
            end
            test_pubsub:close_ws()
        }
    }
--- response_body
ret: test



=== TEST 4: send unregisted command
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            local data = test_pubsub:send_recv_ws({
                sequence = 0,
                cmd_kafka_fetch = {
                    topic = "test",
                    partition = 0,
                    offset = 0,
                },
            })
            if data and data.error_resp then
                ngx.say(data.error_resp.message)
            end
            test_pubsub:close_ws()
        }
    }
--- response_body
unknown command: cmd_kafka_fetch
--- error_log
pubsub callback handler not registered for the command, command: cmd_kafka_fetch
