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

=== TEST 1: sliding window, redis, delayed sync
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
                                "window_type": "sliding",
                                "key_type": "constant",
                                "key": "delayed-sync-stale-snapshot",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "sync_interval": 0.1
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



=== TEST 2: a node that only rejects still refreshes its quota after its local delta expired
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local redis = require("resty.redis")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local function hit()
                local res, err = http.new():request_uri(uri)
                return res and res.status or err
            end

            local function drop_redis_counters()
                local red = redis:new()
                assert(red:connect("127.0.0.1", 6379))
                local keys = assert(red:keys("*delayed-sync-stale-snapshot*"))
                for _, key in ipairs(keys) do
                    red:del(key)
                end
                red:close()
            end

            -- keep all requests inside one 60s sliding window
            local left = 60 - ngx.now() % 60
            if left < 5 then
                ngx.sleep(left + 0.1)
            end
            drop_redis_counters()

            local codes = {hit(), hit(), hit()}
            -- let the delayed sync flush the local delta
            ngx.sleep(0.3)

            -- the local delta key lives two windows from its creation and is
            -- not renewed; drop it as if that time had passed
            local dict = ngx.shared["plugin-limit-count"]
            for _, key in ipairs(dict:get_keys(0)) do
                if key:find("^local_delta#") then
                    dict:delete(key)
                end
            end

            -- free the quota in Redis, as the previous window's weight
            -- decaying or another node's view would
            drop_redis_counters()

            -- judged on the cached quota, which is still exhausted
            codes[4] = hit()
            -- the sync this rejection scheduled must refresh the cached quota
            ngx.sleep(0.3)
            codes[5] = hit()

            ngx.say(table.concat(codes, " "))
        }
    }
--- response_body
200 200 503 503 200
--- timeout: 10
