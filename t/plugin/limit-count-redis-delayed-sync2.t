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
BEGIN {
    $ENV{REDIS_NODE_0} = "127.0.0.1:5000";
    $ENV{REDIS_NODE_1} = "127.0.0.1:5001";
}

use t::APISIX 'no_plan';

master_on();
workers(2);
no_shuffle();
check_accum_error_log();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set route with redis (fixed window, delayed sync)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/echo',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "limit-count": {
                            "count": 7,
                            "time_window": 10,
                            "key_type": "var",
                            "key": "http_host",
                            "show_limit_quota_header": true,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "sync_interval": 0.1,
                            "rejected_code": 503
                        }
                    },
                    "host": "example-1.com",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 2: delayed sync to redis - remaining decreases locally
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-1.com
--- error_code eval
[200, 200, 200, 200]
--- response_headers eval
[
    "X-RateLimit-Remaining: 6",
    "X-RateLimit-Remaining: 5",
    "X-RateLimit-Remaining: 4",
    "X-RateLimit-Remaining: 3",
]



=== TEST 3: delayed sync to redis - reach the limit
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-1.com
--- error_code eval
[200, 200, 200, 503]
--- response_headers eval
[
    "X-RateLimit-Remaining: 2",
    "X-RateLimit-Remaining: 1",
    "X-RateLimit-Remaining: 0",
    "X-RateLimit-Remaining: 0",
]



=== TEST 4: set route with redis-sentinel (fixed window, delayed sync)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/echo',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "limit-count": {
                            "count": 7,
                            "time_window": 10,
                            "key_type": "var",
                            "key": "http_host",
                            "rejected_code": 503,
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                {"host": "127.0.0.1", "port": 26379}
                            ],
                            "redis_master_name": "mymaster",
                            "redis_role": "master",
                            "sync_interval": 0.1,
                            "redis_database": 1
                        }
                    },
                    "host": "example-4.com",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 5: delayed sync to redis-sentinel - remaining decreases locally
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-4.com
--- error_code eval
[200, 200, 200, 200]
--- response_headers eval
[
    "X-RateLimit-Remaining: 6",
    "X-RateLimit-Remaining: 5",
    "X-RateLimit-Remaining: 4",
    "X-RateLimit-Remaining: 3",
]



=== TEST 6: delayed sync to redis-sentinel - reach the limit
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-4.com
--- error_code eval
[200, 200, 200, 503]
--- response_headers eval
[
    "X-RateLimit-Remaining: 2",
    "X-RateLimit-Remaining: 1",
    "X-RateLimit-Remaining: 0",
    "X-RateLimit-Remaining: 0",
]



=== TEST 7: set route with redis-cluster (fixed window, delayed sync)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/echo',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "limit-count": {
                            "count": 7,
                            "time_window": 10,
                            "key_type": "var",
                            "key": "http_host",
                            "rejected_code": 503,
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "$ENV://REDIS_NODE_0",
                                "$ENV://REDIS_NODE_1"
                            ],
                            "redis_cluster_name": "redis-cluster-1",
                            "sync_interval": 0.1
                        }
                    },
                    "host": "example-7.com",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 8: delayed sync to redis-cluster - remaining decreases locally
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-7.com
--- error_code eval
[200, 200, 200, 200]
--- response_headers eval
[
    "X-RateLimit-Remaining: 6",
    "X-RateLimit-Remaining: 5",
    "X-RateLimit-Remaining: 4",
    "X-RateLimit-Remaining: 3",
]



=== TEST 9: delayed sync to redis-cluster - reach the limit
--- pipelined_requests eval
["GET /echo", "GET /echo", "GET /echo", "GET /echo"]
--- more_headers
Host: example-7.com
--- error_code eval
[200, 200, 200, 503]
--- response_headers eval
[
    "X-RateLimit-Remaining: 2",
    "X-RateLimit-Remaining: 1",
    "X-RateLimit-Remaining: 0",
    "X-RateLimit-Remaining: 0",
]
