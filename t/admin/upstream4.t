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

=== TEST 1: set upstream(id: 1 + name: test name)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "name": "test upstream name"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "name": "test upstream name"
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "set"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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



=== TEST 3: string id(delete)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/a-b-c-ABC_0123',
                ngx.HTTP_DELETE
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: invalid string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/*invalid',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the requireds"}



=== TEST 5: retries is 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1,
                        "127.0.0.1:8090": 1
                    },
                    "retries": 0,
                    "type": "roundrobin"
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



=== TEST 6: retries is -1 (INVALID)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1,
                        "127.0.0.1:8090": 1
                    },
                    "retries": -1,
                    "type": "roundrobin"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"retries\" validation failed: expected -1 to be greater than 0"}



=== TEST 7: invalid route: multi nodes with `node` mode to pass host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "httpbin.org:8080": 1,
                        "test.com:8080": 1
                    },
                    "type": "roundrobin",
                    "pass_host": "node"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- skip_nginx: 5: > 1.19.0
--- error_code: 400



=== TEST 8: invalid route: empty `upstream_host` when `pass_host` is `rewrite`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "httpbin.org:8080": 1,
                        "test.com:8080": 1
                    },
                    "type": "roundrobin",
                    "pass_host": "rewrite",
                    "upstream_host": ""
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400



=== TEST 9: set upstream(with labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "labels": {
                        "build":"16",
                        "env":"production",
                        "version":"v2"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "labels": {
                                "build":"16",
                                "env":"production",
                                "version":"v2"
                            }
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: get upstream(with labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "labels": {
                                "version":"v2",
                                "build":"16",
                                "env":"production"
                            }
                        },
                        "key": "/apisix/upstreams/1"
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



=== TEST 11: patch upstream(only labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "labels": {
	                    "build": "17"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "labels": {
                                "version":"v2",
                                "build":"17",
                                "env":"production"
                            }
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: invalid format of label value: set upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "labels": {
	                    "env": ["production", "release"]
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"labels\" validation failed: failed to validate env (matching \".*\"): wrong type: expected string, got table"}



=== TEST 13: patch upstream(whole, create_time)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream",
                    "create_time": 1705252779
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new upstream",
                            "create_time": 1705252779
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            if code >= 300 then
                return
            end

            local res = assert(etcd.get('/upstreams/1'))
            local create_time = res.body.node.value.create_time
            assert(create_time == 1705252779, "create_time mismatched")
        }
    }
--- response_body
passed



=== TEST 14: patch upstream(whole, update_time)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream",
                    "update_time": 1705252779
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new upstream",
                            "create_time": 1705252779
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            if code >= 300 then
                return
            end

            local res = assert(etcd.get('/upstreams/1'))
            local update_time = res.body.node.value.update_time
            assert(update_time == 1705252779, "update_time mismatched")
        }
    }
--- response_body
passed



=== TEST 15: create upstream with create_time and update_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/up_create_update_time',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "create_time": 1602883670,
                    "update_time": 1602893670
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "create_time": 1602883670,
                            "update_time": 1602893670
                        },
                        "key": "/apisix/upstreams/up_create_update_time"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: delete test upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/up_create_update_time',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed



=== TEST 17: patch upstream with sub_path, the data is number
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {},
                    "type": "roundrobin"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            local id = 1
            local res = assert(etcd.get('/upstreams/' .. id))
            local prev_create_time = res.body.node.value.create_time
            local prev_update_time = res.body.node.value.update_time
            ngx.sleep(1)

            local code, message = t('/apisix/admin/upstreams/1/retries',
                 ngx.HTTP_PATCH,
                 json.encode(1)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(message)
            local res = assert(etcd.get('/upstreams/' .. id))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
