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

=== TEST 1: set route, missing redis_cluster_nodes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
{"error_msg":"failed to check the configuration of plugin limit-count err: else clause did not match"}



=== TEST 2: set route, with redis_cluster_nodes and redis_cluster_name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_timeout": 1001,
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: up the limit
--- request
GET /hello
--- error_log
try to lock with key route#1#redis-cluster
unlock with key route#1#redis-cluster



=== TEST 5: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503]



=== TEST 6: up the limit again
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 503, 404, 503, 503]



=== TEST 7: set route, four redis nodes, only one is valid
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 9999,
                            "time_window": 60,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "127.0.0.1:5000",
                                "127.0.0.1:8001",
                                "127.0.0.1:8002",
                                "127.0.0.1:8003"
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: hit route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i = 1, 20 do
                local code, body = t('/hello', ngx.HTTP_GET)
                ngx.say("code: ", code)
            end

        }
    }
--- response_body
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
code: 200
--- timeout: 10



=== TEST 9: update route, use new limit configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function set_route(count)
                t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-count": {
                                "count": ]] .. count .. [[,
                                "time_window": 69,
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
            end

            set_route(2)
            local t = require("lib.test_admin").test
            for i = 1, 5 do
                local code, body = t('/hello', ngx.HTTP_GET)
                ngx.say("code: ", code)
            end

            set_route(3)
            local t = require("lib.test_admin").test
            for i = 1, 5 do
                local code, body = t('/hello', ngx.HTTP_GET)
                ngx.say("code: ", code)
            end
        }
    }
--- response_body
code: 200
code: 200
code: 503
code: 503
code: 503
code: 200
code: 200
code: 200
code: 503
code: 503



=== TEST 10: set route, four redis nodes, no one is valid, with enable degradation switch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 9999,
                            "time_window": 60,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "allow_degradation": true,
                            "redis_cluster_nodes": [
                                "127.0.0.1:8001",
                                "127.0.0.1:8002",
                                "127.0.0.1:8003",
                                "127.0.0.1:8004"
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: enable degradation switch for TEST 10
--- request
GET /hello
--- response_body
hello world
--- error_log
connection refused



=== TEST 12: set route, use error type for redis_cluster_ssl and redis_cluster_ssl_verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_timeout": 1001,
                            "redis_cluster_nodes": [
                                "127.0.0.1:7000",
                                "127.0.0.1:7001"
                            ],
                            "redis_cluster_name": "redis-cluster-1",
                            "redis_cluster_ssl": "true",
                            "redis_cluster_ssl_verify": "false"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
{"error_msg":"failed to check the configuration of plugin limit-count err: else clause did not match"}



=== TEST 13: set route, redis_cluster_ssl_verify is true(will cause ssl handshake err), with enable degradation switch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "allow_degradation": true,
                            "redis_timeout": 1001,
                            "redis_cluster_nodes": [
                                "127.0.0.1:7000",
                                "127.0.0.1:7001"
                            ],
                            "redis_cluster_name": "redis-cluster-1",
                            "redis_cluster_ssl": true,
                            "redis_cluster_ssl_verify": true
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: enable degradation switch for TEST 13
--- request
GET /hello
--- response_body
hello world
--- error_log
failed to do ssl handshake



=== TEST 15: set route, with redis_cluster_nodes and redis_cluster_name redis_cluster_ssl and redis_cluster_ssl_verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_timeout": 1001,
                            "redis_cluster_nodes": [
                                "127.0.0.1:7000",
                                "127.0.0.1:7001"
                            ],
                            "redis_cluster_name": "redis-cluster-1",
                            "redis_cluster_ssl": true,
                            "redis_cluster_ssl_verify": false
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]
