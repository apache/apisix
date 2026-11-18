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



=== TEST 10: set route with multiple rules and delayed sync
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/echo-multi',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "limit-count": {
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 2,
                            "sync_interval": 0.5,
                            "show_limit_quota_header": true,
                            "rejected_code": 503,
                            "rules": [
                                {
                                    "count": 5,
                                    "time_window": 10,
                                    "key": "${remote_addr}_per_minute",
                                    "header_prefix": "rule1"
                                },
                                {
                                    "count": 100,
                                    "time_window": 20,
                                    "key": "${remote_addr}_per_hour",
                                    "header_prefix": "rule2"
                                }
                            ]
                        }
                    },
                    "host": "example-10.com",
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



=== TEST 11: each rule keeps its own remaining after delayed sync
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local function request()
                local res = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/echo", {
                    headers = {
                        Host = "example-10.com",
                    },
                })
                if not res then
                    return nil, "no response"
                end
                return res
            end

            local function header(res, name)
                for k, v in pairs(res.headers) do
                    if k:lower() == name then
                        return tonumber(v)
                    end
                end
                return nil
            end

            local res, err = request()
            if not res then
                ngx.say("FAIL: request before sync: ", err)
                return
            end

            local r1 = header(res, "x-rule1-ratelimit-remaining")
            local r2 = header(res, "x-rule2-ratelimit-remaining")
            if not r1 or not r2 then
                ngx.say("FAIL: missing remaining headers before sync")
                return
            end

            if r1 ~= 4 or r2 ~= 99 then
                ngx.say("FAIL: unexpected remaining before sync, rule1=", r1,
                        ", rule2=", r2)
                return
            end

            -- wait for the delayed sync timer to flush the local deltas to Redis
            ngx.sleep(1)

            res, err = request()
            if not res then
                ngx.say("FAIL: request after sync: ", err)
                return
            end

            r1 = header(res, "x-rule1-ratelimit-remaining")
            r2 = header(res, "x-rule2-ratelimit-remaining")
            if not r1 or not r2 then
                ngx.say("FAIL: missing remaining headers after sync")
                return
            end

            -- the second rule must not be synced through the first rule's
            -- count/time_window
            if r1 ~= 3 or r2 ~= 98 then
                ngx.say("FAIL: rule counters corrupted after sync, rule1=", r1,
                        ", rule2=", r2)
                return
            end

            ngx.say("PASS")
        }
    }
--- response_body
PASS
