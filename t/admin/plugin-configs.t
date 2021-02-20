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

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: PUT
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/plugin_configs/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/plugin_configs/1'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- response_body
passed



=== TEST 2: GET
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/plugin_configs/1"
                    },
                    "action": "get"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: GET all
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_configs',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "dir": true,
                        "nodes": [
                        {
                            "key": "/apisix/plugin_configs/1",
                            "value": {
                            "plugins": {
                                "limit-count": {
                                "time_window": 60,
                                "policy": "local",
                                "count": 2,
                                "key": "remote_addr",
                                "rejected_code": 503
                                }
                            }
                            }
                        }
                        ],
                        "key": "/apisix/plugin_configs"
                    },
                    "action": "get"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: PATCH
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/plugin_configs/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PATCH,
                [[{
                    "plugins": {
                    "limit-count": {
                        "count": 3,
                        "time_window": 60,
                        "rejected_code": 503,
                        "key": "remote_addr"
                    }
                }}]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 3,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/plugin_configs/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/plugin_configs/1'))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- response_body
passed



=== TEST 5: PATCH (sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/plugin_configs/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/plugin_configs/1/plugins',
                ngx.HTTP_PATCH,
                [[{
                    "limit-count": {
                        "count": 2,
                        "time_window": 60,
                        "rejected_code": 503,
                        "key": "remote_addr"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/plugin_configs/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/plugin_configs/1'))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- response_body
passed



=== TEST 6: invalid plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "rejected_code": 503,
                            "time_window": 60,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: property \"count\" is required"}
--- error_code: 400
