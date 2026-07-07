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

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 5,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "window_type": "sliding"
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
            ngx.say(body)
        }
    }
--- response_body
passed
--- wait: 0.2



=== TEST 2: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 3: headers rounded off
# in this test we extract the rate limit header values then extract the decimal part
# to check if the decimal part is longer than 2
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local core = require("apisix.core")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local opt = {method = "GET"}
            local httpc = http.new()

            local headers_to_check = {"X-RateLimit-Remaining", "X-RateLimit-Reset"}
            for i = 1, 5, 1 do
                local res = httpc:request_uri(uri, opt)
                local headers = res.headers

                local m, err = ngx.re.match(headers["X-RateLimit-Remaining"], "\\d(.*)")
                if not m then
                    ngx.status = 500
                    ngx.say("error: ", err)
                    return
                end

                local value = m[1]
                if #value > 0 then
                    ngx.status = 500
                    ngx.say("remaining should be an integer but found float")
                    return
                end

                local m, err = ngx.re.match(headers["X-RateLimit-Reset"], "\\d\\.?(.*)")
                if not m then
                    ngx.status = 500
                    ngx.say("error: ", err)
                    return
                end

                local value = m[1]
                if #value > 2 then
                    ngx.status = 500
                    ngx.say("x-ratelimit-recet decimal value has more than 2 digits")
                    return
                end

                if res.status == 200 then
                    ngx.sleep(1)
                else
                    ngx.sleep(1.5)
                end
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- error_code: 200
--- response_body
passed



=== TEST 4: set route(id: 1) with redis-sentinel
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 5,
                                "rejected_code": 503,
                                "policy": "redis-sentinel",
                                "redis_sentinels": [
                                    {"host": "127.0.0.1", "port": 26379}
                                ],
                                "redis_master_name": "mymaster",
                                "redis_role": "master",
                                "window_type": "sliding",
                                "sync_interval": 0.2,
                                "redis_database": 1
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
            ngx.say(body)
        }
    }
--- response_body
passed
--- wait: 0.2



=== TEST 5: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 6: sliding-window commit() flushes an already-permitted delta even over the limit
# regression: delayed sync must not drop a locally-permitted delta when the
# remote counter is already at/over the limit. incoming() rejects before it
# increments; commit() must still increment so the global count is not lost.
--- config
    location /t {
        content_by_lua_block {
            local sliding_window =
                require("apisix.plugins.limit-count.sliding-window.sliding-window")
            local redis_store =
                require("apisix.plugins.limit-count.sliding-window.store.redis")
            local redis_cli = require("apisix.plugins.limit-count.util").redis_cli
            local conf = {
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 1,
            }
            local limit, window = 2, 5
            local lim, err = sliding_window.new_with_red_cli_factory(
                redis_store, limit, window, redis_cli, conf)
            if not lim then
                ngx.say("failed to create limiter: ", err)
                return
            end

            local key = "ut-commit-" .. ngx.now()
            -- consume the whole quota
            lim:incoming(key, 2)
            -- over the limit now: incoming() must reject and NOT increment
            local _, rejected = lim:incoming(key, 3)
            ngx.say("incoming over limit: ", rejected)
            -- commit() must still increment despite being over the limit
            local delay, remaining = lim:commit(key, 3)
            ngx.say("commit delay: ", tostring(delay), ", remaining: ", remaining)
        }
    }
--- response_body
incoming over limit: rejected
commit delay: 0, remaining: -3



=== TEST 7: sliding-window Redis counters are isolated by plugin_name
# regression: two plugins reusing this module on the same resource with
# identical config produce the same gen_limit_key. Without a plugin_name prefix
# on the Redis counter key they would share a counter and double-count each
# other. limit-count and graphql-limit-count are the real-world pair.
--- config
    location /t {
        content_by_lua_block {
            local sliding_window =
                require("apisix.plugins.limit-count.sliding-window.sliding-window")
            local redis_store =
                require("apisix.plugins.limit-count.sliding-window.store.redis")
            local redis_cli = require("apisix.plugins.limit-count.util").redis_cli
            local conf = {
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 1,
            }
            local limit, window = 2, 5

            local function new_lim(plugin_name)
                local lim = sliding_window.new_with_red_cli_factory(
                    redis_store, limit, window, redis_cli, conf)
                -- production wires plugin_name onto the instance after construction
                lim.plugin_name = plugin_name
                return lim
            end

            local lim_a = new_lim("plugin-limit-count")
            local lim_b = new_lim("plugin-graphql-limit-count")

            -- same resolved key for both plugins
            local key = "ut-isolate-" .. ngx.now()

            -- exhaust plugin A's quota
            lim_a:incoming(key, 2)
            local _, a_rejected = lim_a:incoming(key, 1)
            ngx.say("a over limit: ", a_rejected)

            -- plugin B must still have its own full quota
            local b_delay, b_remaining = lim_b:incoming(key, 1)
            ngx.say("b independent: ", tostring(b_delay), ", remaining: ", b_remaining)
        }
    }
--- response_body
a over limit: rejected
b independent: 0, remaining: 1



=== TEST 8: check_and_incr decides and increments atomically, never on reject
# the accept/reject decision and the increment happen in one atomic step, so
# concurrent requests cannot all pass the check before any increment lands. an
# over-limit request must reject and leave the counter untouched.
--- config
    location /t {
        content_by_lua_block {
            local redis_store =
                require("apisix.plugins.limit-count.sliding-window.store.redis")
            local redis_cli = require("apisix.plugins.limit-count.util").redis_cli
            local conf = {
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 1,
            }
            local red = redis_cli(conf)
            local limit, window, remaining_time, expiry = 2, 5, 5, 10
            local cur = "ut-atomic-cur-" .. ngx.now()
            local last = "ut-atomic-last-" .. ngx.now()

            local function call(cost)
                return redis_store.check_and_incr(redis_store, cur, last, cost,
                                limit, window, remaining_time, expiry, red)
            end

            local r1 = call(1)
            ngx.say("accept ", r1[1], " count ", r1[2])
            local r2 = call(1)
            ngx.say("accept ", r2[1], " count ", r2[2])
            -- over the limit now: must reject and not increment
            local r3 = call(1)
            ngx.say("accept ", r3[1], " count ", r3[2])
            local stored = red:get(cur)
            ngx.say("stored: ", stored)
        }
    }
--- response_body
accept 1 count 1
accept 1 count 2
accept 0 count 2
stored: 2
