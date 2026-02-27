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
log_level('info');

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

=== TEST 1: use variable in count and time_window with default value
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
                                "count": "${http_count ?? 2}",
                                "time_window": "${http_time_window ?? 5}",
                                "rejected_code": 503,
                                "key_type": "var",
                                "key": "remote_addr",
                                "policy": "local"
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



=== TEST 2: request without count/time_window headers
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 3: request with count header
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- more_headers
count: 5
--- error_code eval
[200, 200, 200, 200, 200, 503]



=== TEST 4: request with count and time_window header
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local core = require("apisix.core")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local opt = {method = "GET", headers = { ["count"] = 3, ["time-window"] = "2" }}
            local httpc = http.new()

            for i = 1, 3, 1 do
                local res = httpc:request_uri(uri, opt)
                if res.status ~= 200 then
                    ngx.say("first two requests should return 200, but got " .. res.status)
                    return
                end
                if res.headers["X-RateLimit-Limit"] ~= "3" then
                    ngx.say("X-RateLimit-Limit should be 3, but got " .. core.json.encode(res.headers))
                    return
                end
            end
            local res = httpc:request_uri(uri, opt)
            if res.status ~= 503 then
                ngx.say("third requests should return 503, but got " .. res.status)
                return
            end

            ngx.sleep(2)

            for i = 1, 3, 1 do
                local res = httpc:request_uri(uri, opt)
                if res.status ~= 200 then
                    ngx.say("two requests after sleep 2s should return 200, but got " .. res.status)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
passed
