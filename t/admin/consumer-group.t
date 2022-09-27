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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
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
            local code, body = t('/apisix/admin/consumer_groups/company_a',
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
                    "key": "/apisix/consumer_groups/company_a"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/consumer_groups/company_a'))
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
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                ngx.HTTP_GET,
                nil,
                [[{
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
                    "key": "/apisix/consumer_groups/company_a"
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
            local code, body = t('/apisix/admin/consumer_groups',
                ngx.HTTP_GET,
                nil,
                [[{
                    "total": 1,
                    "list": [
                        {
                            "key": "/apisix/consumer_groups/company_a",
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
                    ]
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
            local res = assert(etcd.get('/consumer_groups/company_a'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/consumer_groups/company_a',
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
                    "key": "/apisix/consumer_groups/company_a"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/consumer_groups/company_a'))
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
            local res = assert(etcd.get('/consumer_groups/company_a'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/consumer_groups/company_a/plugins',
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
                    "key": "/apisix/consumer_groups/company_a"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/consumer_groups/company_a'))
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
            local code, body = t('/apisix/admin/consumer_groups/company_a',
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



=== TEST 7: PUT (with non-plugin fields)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "labels": {
                        "你好": "世界"
                    },
                    "desc": "blah"
                }]],
                [[{
                    "value": {
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "labels": {
                            "你好": "世界"
                        },
                        "desc": "blah"
                    },
                    "key": "/apisix/consumer_groups/company_a"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/consumer_groups/company_a'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- response_body
passed



=== TEST 8: GET (with non-plugin fields)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                ngx.HTTP_GET,
                nil,
                [[{
                    "value": {
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "labels": {
                            "你好": "世界"
                        },
                        "desc": "blah"
                    },
                    "key": "/apisix/consumer_groups/company_a"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: invalid non-plugin fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                ngx.HTTP_PUT,
                [[{
                    "labels": "a",
                    "plugins": {
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- response_body
{"error_msg":"invalid configuration: property \"labels\" validation failed: wrong type: expected object, got string"}
--- error_code: 400



=== TEST 10: set consumer-group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/consumer_groups/company_a',
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
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/consumer_groups/company_a'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- response_body
passed



=== TEST 11: add consumer with group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/foobar',
                ngx.HTTP_PUT,
                [[{
                    "username": "foobar",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-two"
                        }
                    },
                    "group_id": "company_a"
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



=== TEST 12: delete-consumer group failed
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                 ngx.HTTP_DELETE
            )
            ngx.print(body)
        }
    }
--- response_body
{"error_msg":"can not delete this consumer group, consumer [foobar] is still using it now"}



=== TEST 13: delete consumer
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/foobar',
                 ngx.HTTP_DELETE
            )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: delete consumer-group
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                 ngx.HTTP_DELETE
            )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: add consumer with invalid group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/foobar',
                ngx.HTTP_PUT,
                [[{
                    "username": "foobar",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-two"
                        }
                    },
                    "group_id": "invalid_group"
                }]]
                )
            assert(code >= 300)
            ngx.say(body)
        }
    }
--- response_body_like
.*failed to fetch consumer group info by consumer group id.*
