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

=== TEST 1: redis-cluster policy with sliding window - basic N per window
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
                            "time_window": 2,
                            "window_type": "sliding",
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


=== TEST 2: redis-cluster policy with sliding window - enforce N per window
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]


=== TEST 3: redis-cluster policy with sliding window - remaining header on reject
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}

            -- ensure previous windows are expired before starting this test
            ngx.sleep(2.2)

            -- first request: allowed, remaining should be 1
            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, {res.status, res.headers["X-RateLimit-Remaining"]})
            end

            -- second request: allowed, remaining should be 0
            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, {res.status, res.headers["X-RateLimit-Remaining"]})
            end

            -- third request: rejected, remaining header should stay at 0
            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, {res.status, res.headers["X-RateLimit-Remaining"]})
            end

            ngx.say(json.encode(ress))
        }
    }
--- response_body
[[200,"1"],[200,"0"],[503,"0"]]


=== TEST 4: redis-cluster policy with sliding window - allow after window passes
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local codes = {}

            -- ensure previous windows are expired before starting this test
            ngx.sleep(2.2)

            -- consume full quota
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(codes, res.status)
            end

            -- wait longer than the sliding window (2s)
            ngx.sleep(2.2)

            -- should be allowed again after window has passed
            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(codes, res.status)
            end

            ngx.say(json.encode(codes))
        }
    }
--- response_body
[200,200,200]


=== TEST 5: redis-cluster policy with sliding window - enforce N per window under burst traffic
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/10',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/burst-cluster",
                    "plugins": {
                        "limit-count": {
                            "count": 3,
                            "time_window": 2,
                            "window_type": "sliding",
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


=== TEST 6: redis-cluster policy with sliding window - only N requests allowed in a burst
--- pipelined_requests eval
[
    "GET /burst-cluster",
    "GET /burst-cluster",
    "GET /burst-cluster",
    "GET /burst-cluster",
    "GET /burst-cluster",
    "GET /burst-cluster"
]
--- error_code eval
[200, 200, 200, 503, 503, 503]


