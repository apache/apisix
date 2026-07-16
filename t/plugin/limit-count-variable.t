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



=== TEST 5: use variable in count -- dynamic updates to `count` should bring immediate effect to X-RateLimit-Remaining
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
                                "time_window": 10,
                                "rejected_code": 503,
                                "key_type": "var",
                                "key": "remote_addr",
                                "window_type": "fixed"
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



=== TEST 6: request with varying count header
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local core = require("apisix.core")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- request with count=3
            local opt_3 = {method = "GET", headers = { ["count"] = 3 }}
            local res = httpc:request_uri(uri, opt_3)

            if res.status ~= 200 then
                ngx.say("first request should return 200, but got " .. res.status)
                return
            end
            if res.headers["x-ratelimit-remaining"] ~= "2" then
                ngx.say("x-ratelimit-remaining should be 2, but got " .. core.json.encode(res.headers))
                return
            end

            -- request with count=2
            local opt_2 = {method = "GET", headers = { ["count"] = 2 }}
            local res = httpc:request_uri(uri, opt_2)
            if res.headers["x-ratelimit-remaining"] ~= "0" then
                ngx.say("x-ratelimit-remaining should be 0, but got " .. core.json.encode(res.headers))
                return
            end

            -- request with count=5
            local opt_2 = {method = "GET", headers = { ["count"] = 5 }}
            local res = httpc:request_uri(uri, opt_2)
            if res.headers["x-ratelimit-remaining"] ~= "2" then
                ngx.say("x-ratelimit-remaining should be 2, but got " .. core.json.encode(res.headers))
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
passed



=== TEST 7: use variable in count
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
                                "time_window": 10,
                                "key_type": "var",
                                "key": "http_host"
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



=== TEST 8: check access log contains rate_limiting_info
--- request
GET /hello
--- more_headers
host: test.com
--- extra_yaml_config
nginx_config:
    http:
        access_log_format: main '$rate_limiting_info';
--- error_code: 200
--- access_log eval
qr/\{\\x22rate_limiting_key\\x22:\\x22\/apisix\/routes\/1:\d+:test\.com\\x22,\\x22rate_limiting_limit\\x22:2,\\x22rate_limiting_remaining\\x22:1,\\x22rate_limiting_reset\\x22:10}/



=== TEST 9: set up route with count/time_window from request variables
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



=== TEST 10: a client-supplied 0/negative/fractional count is rejected, not bypassed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            for _, count in ipairs({"0", "-1", "1.5", "9999999999999999"}) do
                local res = httpc:request_uri(uri, {method = "GET",
                                                    headers = {["count"] = count}})
                if res.status ~= 500 then
                    ngx.say("count=", count, " should be rejected with 500, got ", res.status)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
resolved value must be a positive number
resolved value must be an integer
resolved value exceeds safe integer range



=== TEST 11: a client-supplied 0/negative/fractional time_window is rejected, not bypassed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            for _, time_window in ipairs({"0", "-1", "1.5", "9999999999999999"}) do
                local res = httpc:request_uri(uri, {method = "GET",
                                                    headers = {["time_window"] = time_window}})
                if res.status ~= 500 then
                    ngx.say("time_window=", time_window, " should be rejected with 500, got ",
                            res.status)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
resolved value must be a positive number
resolved value must be an integer
resolved value exceeds safe integer range



=== TEST 12: set up rules-mode route with count from a request variable
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
                                "rejected_code": 503,
                                "rules": [
                                    {
                                        "key": "${http_user}",
                                        "count": "${http_count ?? 2}",
                                        "time_window": 60
                                    }
                                ]
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



=== TEST 13: rules-mode invalid count rejects, not silently skips the rule
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            -- the rule's key resolves (user header present), so without bounds
            -- validation a count of 0 would drop the rule and let the request pass
            local res = httpc:request_uri(uri, {method = "GET",
                                headers = {["user"] = "jack", ["count"] = "0"}})
            if res.status ~= 500 then
                ngx.say("invalid rule count should be rejected with 500, got ", res.status)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
resolved value must be a positive number
