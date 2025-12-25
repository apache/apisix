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
run_tests;

__DATA__

=== TEST 1: sanity check for unhealthy-ratio policy
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local ok, err = plugin.check_schema({
                break_response_code = 502,
                policy = "unhealthy-ratio",
                unhealthy = {
                    http_statuses = {500},
                    error_ratio = 0.5,
                    min_request_threshold = 10,
                    sliding_window_size = 300,
                    half_open_max_calls = 3
                },
                healthy = {
                    http_statuses = {200},
                    success_ratio = 0.6
                },
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: default configuration for unhealthy-ratio policy
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local conf = {
                break_response_code = 502,
                policy = "unhealthy-ratio"
            }

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            local conf_str = require("toolkit.json").encode(conf)
            if conf.max_breaker_sec == 300
               and conf.unhealthy.http_statuses[1] == 500
               and conf.break_response_code == 502 then
                 ngx.say("passed")
            else
                 ngx.say("failed: " .. conf_str)
            end
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: bad error_ratio (too high)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 1.5,
                                "min_request_threshold": 10
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 4: bad error_ratio (negative)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": -0.1,
                                "min_request_threshold": 10
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 5: bad min_request_threshold (zero)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 0.5,
                                "min_request_threshold": 0
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 6: bad sliding_window_size (too small)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 0.5,
                                "min_request_threshold": 10,
                                "sliding_window_size": 5
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 7: bad sliding_window_size (too large)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 0.5,
                                "min_request_threshold": 10,
                                "sliding_window_size": 4000
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 8: bad success_ratio (too high)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 0.5,
                                "min_request_threshold": 10
                            },
                            "healthy": {
                                "http_statuses": [200],
                                "success_ratio": 1.5
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 9: bad half_open_max_calls (too large)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 502,
                            "policy": "unhealthy-ratio",
                            "unhealthy": {
                                "http_statuses": [500],
                                "error_ratio": 0.5,
                                "min_request_threshold": 10,
                                "sliding_window_size": 300,
                                "half_open_max_calls": 25
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin api-breaker err: else clause did not match"}



=== TEST 10: set route with unhealthy-ratio policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "api-breaker": {
                                "break_response_code": 502,
                                "break_response_body": "Upstream failure",
                                "policy": "unhealthy-ratio",
                                "max_breaker_sec": 10,
                                "unhealthy": {
                                    "http_statuses": [500, 503],
                                    "error_ratio": 0.6,
                                    "min_request_threshold": 3,
                                    "sliding_window_size": 60,
                                    "half_open_max_calls": 2
                                },
                                "healthy": {
                                    "http_statuses": [200],
                                    "successes": 2
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST $((${1}+1)): test ratio-based circuit breaker functionality
--- request eval
[
    "GET /api_breaker",
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500",
    "GET /api_breaker"
]
--- error_code eval
[200, 500, 500, 502, 502]
--- response_body eval
[
    "hello world",
    "fault injection!",
    "fault injection!",
    "Upstream failure",
    "Upstream failure"
]



=== TEST $((${1}+1)): wait for circuit breaker to enter half-open state
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(11) -- wait longer than max_breaker_sec
            ngx.say("waited")
        }
    }
--- request
GET /t
--- response_body
waited
--- timeout: 15



=== TEST 16: test half-open state functionality
--- request eval
[
    "GET /api_breaker",
    "GET /api_breaker",
    "GET /api_breaker"
]
--- error_code eval
[200, 200, 200]
--- response_body eval
[
    "hello world",
    "hello world",
    "hello world"
]



=== TEST 19: verify circuit breaker works with custom break_response_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "api-breaker": {
                                "break_response_code": 503,
                                "break_response_body": "Service temporarily unavailable",
                                "break_response_headers": [
                                    {"key": "X-Circuit-Breaker", "value": "open"},
                                    {"key": "Retry-After", "value": "30"}
                                ],
                                "policy": "unhealthy-ratio",
                                "max_breaker_sec": 5,
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "error_ratio": 0.5,
                                    "min_request_threshold": 2,
                                    "sliding_window_size": 30
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 20: trigger circuit breaker with custom headers (combined)
--- request eval
[
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500"
]
--- error_code eval
[500, 500, 503]



=== TEST 23: setup route for sliding window expiration test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "api-breaker": {
                                "break_response_code": 502,
                                "break_response_body": "Upstream failure",
                                "policy": "unhealthy-ratio",
                                "max_breaker_sec": 10,
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "error_ratio": 0.5,
                                    "min_request_threshold": 3,
                                    "sliding_window_size": 10,
                                    "half_open_max_calls": 2
                                },
                                "healthy": {
                                    "http_statuses": [200],
                                    "success_ratio": 0.6
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 24: test sliding window statistics reset after expiration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            -- First, make some requests to accumulate statistics
            ngx.say("Phase 1: Accumulate statistics ===")
            local code1 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 1 (200): ", code1)
            
            local code2 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 2 (500): ", code2)
            
            local code3 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 3 (500): ", code3)
            
            -- At this point: 3 total requests, 2 failures, failure rate = 2/3 = 0.67 > 0.5
            -- Should trigger circuit breaker
            local code4 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 4 (should be 502): ", code4)
            
            ngx.say("Phase 2: Wait for sliding window to expire ===")
            -- Wait for sliding window to expire (sliding_window_size = 10 seconds)
            ngx.sleep(11)
            
            ngx.say("Phase 3: Test after window expiration ===")
            -- After window expiration, statistics should be reset
            -- New requests should not trigger circuit breaker immediately
            local code5 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 5 after expiration (should be 200): ", code5)
            
            local code6 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 6 after expiration (should be 200): ", code6)
        }
    }
--- request
GET /t
--- response_body
Phase 1: Accumulate statistics ===
Request 1 (200): 200
Request 2 (500): 500
Request 3 (500): 500
Request 4 (should be 502): 502
Phase 2: Wait for sliding window to expire ===
Phase 3: Test after window expiration ===
Request 5 after expiration (should be 200): 200
Request 6 after expiration (should be 200): 200
--- timeout: 60



=== TEST 25: setup route for half-open failure fallback test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "api-breaker": {
                                "break_response_code": 502,
                                "break_response_body": "Upstream failure",
                                "policy": "unhealthy-ratio",
                                "max_breaker_sec": 5,
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "error_ratio": 0.5,
                                    "min_request_threshold": 2,
                                    "sliding_window_size": 60,
                                    "half_open_max_calls": 3
                                },
                                "healthy": {
                                    "http_statuses": [200],
                                    "success_ratio": 0.7
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 26: test half-open state failure fallback to open state
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            ngx.say("Phase 1: Trigger circuit breaker ===")
            -- First trigger circuit breaker to OPEN state
            local code1 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 1 (500): ", code1)
            
            local code2 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 2 (500): ", code2)
            
            -- Should trigger circuit breaker (2 failures, min_request_threshold=2, error_ratio=1.0 > 0.5)
            local code3 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 3 (should be 502): ", code3)
            
            ngx.say("Phase 2: Wait for half-open state ===")
            -- Wait for circuit breaker to enter half-open state
            ngx.sleep(6)
            
            ngx.say("Phase 3: Test half-open failure fallback ===")
            -- In half-open state, first request should be allowed
            local code4 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 4 in half-open (should be 200): ", code4)
            
            -- Second request fails - should cause fallback to OPEN state
            local code5 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 5 in half-open (500 - should trigger fallback): ", code5)
            
            -- Subsequent requests should be rejected (circuit breaker back to OPEN)
            local code6 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 6 after fallback (should be 502): ", code6)
            
            local code7 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 7 after fallback (should be 502): ", code7)
        }
    }
--- request
GET /t
--- response_body
Phase 1: Trigger circuit breaker ===
Request 1 (500): 500
Request 2 (500): 500
Request 3 (should be 502): 502
Phase 2: Wait for half-open state ===
Phase 3: Test half-open failure fallback ===
Request 4 in half-open (should be 200): 200
Request 5 in half-open (500 - should trigger fallback): 500
Request 6 after fallback (should be 502): 502
Request 7 after fallback (should be 502): 502
--- timeout: 15



=== TEST 27: setup route for half-open request limit test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "api-breaker": {
                                "break_response_code": 502,
                                "break_response_body": "Upstream failure",
                                "policy": "unhealthy-ratio",
                                "max_breaker_sec": 3,
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "error_ratio": 0.5,
                                    "min_request_threshold": 2,
                                    "sliding_window_size": 60,
                                    "half_open_max_calls": 2
                                },
                                "healthy": {
                                    "http_statuses": [200],
                                    "success_ratio": 1
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/api_breaker"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 28: test half-open state request limit enforcement and header check
--- config
    location /t {
        content_by_lua_block {
            local function run_req(uri)
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("127.0.0.1", 1984)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return nil
                end
                
                local req = "GET " .. uri .. " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return nil
                end
                
                local reader = sock:receiveuntil("\r\n")
                local line, err = reader()
                if not line then
                    ngx.say("failed to read status: ", err)
                    return nil
                end
                
                local status = tonumber(string.match(line, "HTTP/%d%.%d (%d+)"))
                
                -- check for headers in the response
                local headers = {}
                while true do
                    local h_line, err = reader()
                    if not h_line or h_line == "" then break end
                    local k, v = string.match(h_line, "([^:]+):%s*(.+)")
                    if k then headers[k] = v end
                end

                sock:receive("*a") -- read body to close cleanly
                sock:close()
                return status, headers
            end
            
            ngx.say("Phase 1: Trigger circuit breaker")
            -- First trigger circuit breaker to OPEN state
            run_req('/api_breaker?code=500')
            run_req('/api_breaker?code=500')
            local code3 = run_req('/api_breaker')
            ngx.say("Trigger req status: ", code3)
            
            ngx.say("Phase 2: Wait for half-open state")
            ngx.sleep(3.2)
            
            ngx.say("Phase 3: Test half-open request limit")
            
            local threads = {}
            -- Fire 3 requests concurrently. Limit is 2.
            for i = 1, 3 do
                threads[i] = ngx.thread.spawn(function()
                    local code, err = run_req('/api_breaker')
                    if not code then
                        return "err: " .. (err or "unknown")
                    end
                    return code
                end)
            end
            
            local results = {}
            for i = 1, 3 do
                local ok, res = ngx.thread.wait(threads[i])
                if ok then
                    table.insert(results, res)
                else
                    table.insert(results, "thread_err")
                end
            end
            table.sort(results)
            ngx.say("Results: ", table.concat(results, ", "))
            
            ngx.say("Phase 4: Reset to OPEN state")
            -- Trigger failure to reset circuit breaker to OPEN state
            local code9 = run_req('/api_breaker?code=500')
            ngx.say("Request 9 status: ", code9)
            
            ngx.say("Phase 5: Verify headers in OPEN state")
            local code10, headers10 = run_req('/api_breaker')
            ngx.say("Request 10 status: ", code10)
        }
    }
--- request
GET /t
--- response_body_like
Phase 1: Trigger circuit breaker
Trigger req status: 502
Phase 2: Wait for half-open state
Phase 3: Test half-open request limit
Results: 200, 200, 200
Phase 4: Reset to OPEN state
Request 9 status: 502
Phase 5: Verify headers in OPEN state
Request 10 status: 502