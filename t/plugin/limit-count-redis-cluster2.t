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

=== TEST 1: set route, use error type for redis_cluster_ssl and redis_cluster_ssl_verify
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
--- error_log
Expected comma or object end but found T_STRING



=== TEST 2: set route, with redis_cluster_nodes and redis_cluster_name redis_cluster_ssl and redis_cluster_ssl_verify
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



=== TEST 3: up the limit
--- request
GET /hello
--- error_log
try to lock with key route#1#redis-cluster
unlock with key route#1#redis-cluster



=== TEST 4: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503]



=== TEST 5: set route, redis_cluster_ssl_verify is true(will cause ssl handshake err), with enable degradation switch
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



=== TEST 6: enable degradation switch for TEST 5
--- request
GET /hello
--- response_body
hello world
--- error_log
failed to do ssl handshake
