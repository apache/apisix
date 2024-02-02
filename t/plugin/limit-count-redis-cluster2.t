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

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: update route, use new limit configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello2",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 60,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "127.0.0.1:5000",
                                "127.0.0.1:5001"
                            ],
                            "redis_cluster_name": "redis-cluster-1"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            local old_X_RateLimit_Reset = 61
            for i = 1, 3 do
                local _, _, headers = t('/hello2', ngx.HTTP_GET)
                ngx.sleep(1)
                if tonumber(headers["X-RateLimit-Reset"]) < old_X_RateLimit_Reset then
                    old_X_RateLimit_Reset = tonumber(headers["X-RateLimit-Reset"])
                    ngx.say("OK")
                else
                   ngx.say("WRONG")
                end
            end
            ngx.say("Done")
        }
    }
--- response_body
OK
OK
OK
Done



=== TEST 2: test header X-RateLimit-Reset shouldn't be set to 0 after request be rejected
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello2",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "127.0.0.1:5000",
                                "127.0.0.1:5001"
                            ],
                            "redis_cluster_name": "redis-cluster-1"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            for i = 1, 3 do
                local _, _, headers = t('/hello2', ngx.HTTP_GET)
                ngx.sleep(1)
                if tonumber(headers["X-RateLimit-Reset"]) > 0 then
                    ngx.say("OK")
                else
                   ngx.say("WRONG")
                end
            end
            ngx.say("Done")
        }
    }
--- response_body
OK
OK
OK
Done
