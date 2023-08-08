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
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set upstream(kafka scheme)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka"
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: set upstream(empty tls)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka",
                "tls": {}
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: set upstream(tls without verify)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka",
                "tls": {
                    "verify": false
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: prepare upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:1980": 1
                },
                "type": "roundrobin"
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

        }
    }
--- response_body
passed



=== TEST 5: prepare route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                },
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

        }
    }
--- response_body
passed



=== TEST 6: delete upstream when plugin in route still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in route [1] is still using it now"}



=== TEST 7: delete route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: prepare service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/services/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: delete upstream when plugin in service still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in service [1] is still using it now"}



=== TEST 10: delete service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/services/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: prepare global_rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t("/apisix/admin/global_rules/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: delete upstream when plugin in global_rule still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in global_rules [1] is still using it now"}



=== TEST 13: delete global_rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/global_rules/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: prepare plugin_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t("/apisix/admin/plugin_configs/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: delete upstream when plugin in plugin_config still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in plugin_config [1] is still using it now"}



=== TEST 16: delete plugin_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/plugin_configs/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 17: prepare consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t("/apisix/admin/consumers", ngx.HTTP_PUT, [[{
                "username": "test",
                "plugins": {
                    "key-auth": {
                        "key": "auth-one"
                    },
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: delete upstream when plugin in consumer still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in consumer [test] is still using it now"}



=== TEST 19: delete consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/consumers/test", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: prepare consumer_group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t("/apisix/admin/consumer_groups/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "key-auth": {
                        "key": "auth-one"
                    },
                    "traffic-split": {
                        "rules": [
                            {
                                "weighted_upstreams": [
                                    {
                                        "upstream_id": 1,
                                        "weight": 1
                                    },
                                    {
                                        "weight": 1
                                    }
                                ]
                            }
                        ]
                    }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: delete upstream when plugin in consumer_group still refer it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, plugin in consumer_group [1] is still using it now"}



=== TEST 22: delete consumer_group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/consumer_groups/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: delete upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/upstreams/1", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
