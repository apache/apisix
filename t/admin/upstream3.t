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

=== TEST 1: list empty resources
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/upstreams',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"get","count":0,"node":{"dir":true,"key":"/apisix/upstreams","nodes":{}}}



=== TEST 2: retry_timeout is -1 (INVALID)
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
                    "retry_timeout": -1,
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
{"error_msg":"invalid configuration: property \"retry_timeout\" validation failed: expected -1 to be greater than 0"}



=== TEST 3: provide upstream for patch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1,
                        "127.0.0.1:8090": 1
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



=== TEST 4: patch upstream(whole)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")

            local id = 1
            local res = assert(etcd.get('/upstreams/' .. id))
            local prev_create_time = res.body.node.value.create_time
            local prev_update_time = res.body.node.value.update_time
            ngx.sleep(1)

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new upstream"
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/upstreams/' .. id))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- response_body
passed



=== TEST 5: patch upstream(new desc)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "desc": "new 21 upstream"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new 21 upstream"
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



=== TEST 6: patch upstream(new nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8081": 3,
                        "127.0.0.1:8082": 4
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1,
                                "127.0.0.1:8081": 3,
                                "127.0.0.1:8082": 4
                            },
                            "type": "roundrobin",
                            "desc": "new 21 upstream"
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: patch upstream(weight is 0)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8081": 3,
                        "127.0.0.1:8082": 0
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8081": 3,
                                "127.0.0.1:8082": 0
                            },
                            "type": "roundrobin",
                            "desc": "new 21 upstream"
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: patch upstream(whole - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1/',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream 24"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new upstream 24"
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



=== TEST 9: patch upstream(new desc - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1/desc',
                ngx.HTTP_PATCH,
                '"new 25 upstream"',
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "desc": "new 25 upstream"
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



=== TEST 10: patch upstream(new nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1/nodes',
                ngx.HTTP_PATCH,
                [[{
                    "127.0.0.6:8081": 3,
                    "127.0.0.7:8082": 4
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.6:8081": 3,
                                "127.0.0.7:8082": 4
                            },
                            "type": "roundrobin",
                            "desc": "new 25 upstream"
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: patch upstream(weight is 0 - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1/nodes',
                ngx.HTTP_PATCH,
                [[{
                    "127.0.0.7:8081": 0,
                    "127.0.0.8:8082": 4
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.7:8081": 0,
                                "127.0.0.8:8082": 4
                            },
                            "type": "roundrobin",
                            "desc": "new 25 upstream"
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: set upstream(type: chash)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "server_name",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13:  wrong upstream key, hash_on default vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1,
                        "127.0.0.1:8081": 2
                    },
                    "type": "chash",
                    "key": "not_support",
                    "desc": "new upstream"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: failed to match pattern \"^((uri|server_name|server_addr|request_uri|remote_port|remote_addr|query_string|host|hostname)|arg_[0-9a-zA-z_-]+)$\" with \"not_support\""}



=== TEST 14: set upstream with args(type: chash)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "arg_device_id",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: set upstream(type: chash)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "server_name",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16:  wrong upstream key, hash_on default vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1,
                        "127.0.0.1:8081": 2
                    },
                    "type": "chash",
                    "key": "not_support",
                    "desc": "new upstream"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: failed to match pattern \"^((uri|server_name|server_addr|request_uri|remote_port|remote_addr|query_string|host|hostname)|arg_[0-9a-zA-z_-]+)$\" with \"not_support\""}



=== TEST 17: set upstream with args(type: chash)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "arg_device_id",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: type chash, hash_on: vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "arg_device_id",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "vars",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 19: type chash, hash_on: header, header name with '_', underscores_in_headers on
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "custom_header",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "header",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: type chash, hash_on: header, header name with invalid character
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "$#^@",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "header",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: failed to match pattern \"^[a-zA-Z0-9-_]+$\" with \"$#^@\""}



=== TEST 21: type chash, hash_on: cookie
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "custom_cookie",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "cookie",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 22: type chash, hash_on: cookie, cookie name with invalid character
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "$#^@abc",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "cookie",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: failed to match pattern \"^[a-zA-Z0-9-_]+$\" with \"$#^@abc\""}



=== TEST 23: type chash, hash_on: consumer, do not need upstream key
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
                    "type": "chash",
                    "hash_on": "consumer",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 24: type chash, hash_on: consumer, set key but invalid
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
                    "type": "chash",
                    "hash_on": "consumer",
                    "key": "invalid-key",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: type chash, invalid hash_on type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "dsadas",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash",
                    "hash_on": "aabbcc",
                    "desc": "new chash upstream"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"hash_on\" validation failed: matches none of the enum values"}
