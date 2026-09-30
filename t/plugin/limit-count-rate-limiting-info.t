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
log_level('info');

add_block_preprocessor(sub {
    my ($block) = @_;

    # `--- limit_count` holds the plugin conf of a route whose log phase logs
    # $rate_limiting_info through lib.rate_limiting_info
    my $limit_count = $block->limit_count;
    if ($limit_count) {
        $block->set_value("config", <<_EOC_);
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local conf = core.json.decode([=[$limit_count]=])
            -- a fresh counter on every run, so that a rerun sees the same counts
            conf.key_type = "constant"
            conf.key = "rl-info-" .. ngx.now() .. "-" .. math.random(1e9)
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/hello",
                    plugins = {
                        ["limit-count"] = conf,
                        ["serverless-post-function"] = {
                            phase = "log",
                            functions = {
                                "return function() require('lib.rate_limiting_info').log() end"
                            },
                        },
                    },
                    upstream = {
                        nodes = {["127.0.0.1:1980"] = 1},
                        type = "roundrobin",
                    },
                }))
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
_EOC_
        $block->set_value("response_body", "passed\n");
    }

    # `--- send_requests` sends that many requests to the route one by one,
    # and prints their status codes
    my $send_requests = $block->send_requests;
    if ($send_requests) {
        $block->set_value("config", <<_EOC_);
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            -- keep the requests inside one 60s sliding window
            local left = 60 - ngx.now() % 60
            if left < 2 then
                ngx.sleep(left + 0.1)
            end
            local codes = {}
            for i = 1, $send_requests do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                codes[i] = res.status
            end
            ngx.say(table.concat(codes, " "))
        }
    }
_EOC_
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: local fixed window
--- limit_count
{"count": 2, "time_window": 60, "policy": "local", "window_type": "fixed"}



=== TEST 2: the first request creates the window, the rejected one has no count
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: fixed allowed cost=1 count=1 created=true window=ok previous_window=absent
rate limiting info: fixed allowed cost=1 count=2 created=false window=ok previous_window=absent
rate limiting info: fixed rejected cost=1 count=null created=false window=ok previous_window=absent



=== TEST 3: local sliding window
--- limit_count
{"count": 2, "time_window": 60, "policy": "local", "window_type": "sliding"}



=== TEST 4: a rejected request adds nothing to the sliding window
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: sliding allowed cost=1 count=1 window=ok previous_count=0
rate limiting info: sliding allowed cost=1 count=2 window=ok previous_count=0
rate limiting info: sliding rejected cost=0 count=2 window=ok previous_count=0



=== TEST 5: redis fixed window
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis", "redis_host": "127.0.0.1",
 "window_type": "fixed"}



=== TEST 6: the redis counter also counts the rejected request
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: fixed allowed cost=1 count=1 created=null window=ok previous_window=absent
rate limiting info: fixed allowed cost=1 count=2 created=null window=ok previous_window=absent
rate limiting info: fixed rejected cost=1 count=3 created=null window=ok previous_window=absent



=== TEST 7: redis sliding window
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis", "redis_host": "127.0.0.1",
 "window_type": "sliding"}



=== TEST 8: redis sliding window details
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: sliding allowed cost=1 count=1 window=ok previous_count=0
rate limiting info: sliding allowed cost=1 count=2 window=ok previous_count=0
rate limiting info: sliding rejected cost=0 count=2 window=ok previous_count=0



=== TEST 9: redis fixed window with delayed sync
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis", "redis_host": "127.0.0.1",
 "window_type": "fixed", "sync_interval": 10}



=== TEST 10: delayed sync reports the synced count and the unsynced local delta
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: fixed allowed cost=1 synced_count=0 local_delta=0 synced_at=ok count=1 created=null window=ok previous_window=absent
rate limiting info: fixed allowed cost=1 synced_count=0 local_delta=1 synced_at=ok count=2 created=null window=ok previous_window=absent
rate limiting info: fixed rejected cost=0 synced_count=0 local_delta=2 synced_at=ok count=2 created=null window=ok previous_window=absent



=== TEST 11: redis sliding window with delayed sync
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis", "redis_host": "127.0.0.1",
 "window_type": "sliding", "sync_interval": 10}



=== TEST 12: delayed sync reports the sliding window as of the last sync
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: sliding allowed cost=1 synced_count=0 local_delta=0 synced_at=ok count=1 window=ok previous_count=0
rate limiting info: sliding allowed cost=1 synced_count=0 local_delta=1 synced_at=ok count=2 window=ok previous_count=0
rate limiting info: sliding rejected cost=0 synced_count=0 local_delta=2 synced_at=ok count=2 window=ok previous_count=0



=== TEST 13: redis-cluster fixed window
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis-cluster",
 "redis_cluster_nodes": ["127.0.0.1:5000", "127.0.0.1:5001"],
 "redis_cluster_name": "redis-cluster-1", "window_type": "fixed"}



=== TEST 14: redis-cluster fixed window details
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: fixed allowed cost=1 count=1 created=null window=ok previous_window=absent
rate limiting info: fixed allowed cost=1 count=2 created=null window=ok previous_window=absent
rate limiting info: fixed rejected cost=1 count=3 created=null window=ok previous_window=absent



=== TEST 15: redis-cluster sliding window with delayed sync
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis-cluster",
 "redis_cluster_nodes": ["127.0.0.1:5000", "127.0.0.1:5001"],
 "redis_cluster_name": "redis-cluster-1", "window_type": "sliding", "sync_interval": 10}



=== TEST 16: redis-cluster sliding window details with delayed sync
--- send_requests: 3
--- response_body
200 200 503
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: sliding allowed cost=1 synced_count=0 local_delta=0 synced_at=ok count=1 window=ok previous_count=0
rate limiting info: sliding allowed cost=1 synced_count=0 local_delta=1 synced_at=ok count=2 window=ok previous_count=0
rate limiting info: sliding rejected cost=0 synced_count=0 local_delta=2 synced_at=ok count=2 window=ok previous_count=0



=== TEST 17: redis unreachable, degraded
--- limit_count
{"count": 2, "time_window": 60, "policy": "redis", "redis_host": "127.0.0.1",
 "redis_port": 16379, "allow_degradation": true}



=== TEST 18: a failed limiter reports only the decision
--- send_requests: 1
--- response_body
200
--- grep_error_log eval
qr/rate limiting info: .*?(?= while logging request)/
--- grep_error_log_out
rate limiting info: fixed error cost=absent current_window=absent
--- error_log
failed to limit count
