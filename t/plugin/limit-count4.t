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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

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

=== TEST 1: set route, counter will be shared
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
                            "count": 1,
                            "time_window": 60
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



=== TEST 2: test X-RateLimit-Reset second number could be decline
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local old_X_RateLimit_Reset = 61
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.sleep(2)
                if tonumber(res.headers["X-RateLimit-Reset"]) < old_X_RateLimit_Reset then
                    old_X_RateLimit_Reset = tonumber(res.headers["X-RateLimit-Reset"])
                    ngx.say("OK")
                else
                   ngx.say("WRONG")
                end
            end
            ngx.say("Done")
        }
    }
--- response_body
OK
OK
Done



=== TEST 3: set route, counter will be shared
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
                            "time_window": 60
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



=== TEST 4: test header X-RateLimit-Remaining exist when limit rejected
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.sleep(1)
                table.insert(ress, res.headers["X-RateLimit-Remaining"])

            end
            ngx.say(json.encode(ress))
        }
    }
--- response_body
["1","0","0"]



=== TEST 5: modified limit-count.incoming, cost == 2
--- config
    location = /t {
        content_by_lua_block {
            local limit_count_local = require "apisix.plugins.limit-count.limit-count-local"
            local lim = limit_count_local.new("limit-count", 10, 60)
            local uri = ngx.var.uri
            for i = 1, 7 do
                local delay, err = lim.limt_count:handle_incoming(uri, 2, true)
                if not delay then
                    ngx.say(err)
                else
                    local remaining = err
                    ngx.say("remaining: ", remaining)
                end
            end
        }
    }
--- request
    GET /t
--- response_body
remaining: 8
remaining: 6
remaining: 4
remaining: 2
remaining: 0
rejected
rejected
--- no_error_log
[error]
[lua]



=== TEST 6: modified limit-count.incoming, cost < 1
--- config
    location = /t {
        content_by_lua_block {
            local limit_count_local = require "apisix.plugins.limit-count.limit-count-local"
            local lim = limit_count_local.new("limit-count", 3, 60)
            local uri = ngx.var.uri
            local delay, err = lim.limt_count:handle_incoming(uri, -2, true)
            if not delay then
                ngx.say(err)
            else
                local remaining = err
                ngx.say("remaining: ", remaining)
            end
        }
    }
--- request
    GET /t
--- response_body
cost must be at least 1
