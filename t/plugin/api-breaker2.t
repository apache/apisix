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

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"break_response_code":502,"healthy":{"http_statuses":[200],"success_ratio":0.6},"max_breaker_sec":300,"policy":"unhealthy-ratio","unhealthy":{"error_ratio":0.5,"http_statuses":[500],"min_request_threshold":10,"half_open_max_calls":3,"sliding_window_size":300}}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"error_ratio\" validation failed: expected 1.5 to be at most 1"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"error_ratio\" validation failed: expected -0.1 to be at least 0"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"min_request_threshold\" validation failed: expected 0 to be at least 1"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"sliding_window_size\" validation failed: expected 5 to be at least 10"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"sliding_window_size\" validation failed: expected 4000 to be at most 3600"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"healthy\" validation failed: property \"success_ratio\" validation failed: expected 1.5 to be at most 1"}



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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"half_open_max_calls\" validation failed: expected 25 to be at most 20"}



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



=== TEST 20: trigger circuit breaker with custom headers
--- request
GET /api_breaker?code=500
--- error_code: 500



=== TEST 21: trigger circuit breaker again
--- request
GET /api_breaker?code=500
--- error_code: 503
--- response_body
Service temporarily unavailable
--- response_headers
X-Circuit-Breaker: open
Retry-After: 30



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
                                    "sliding_window_size": 5,
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
            ngx.say("=== Phase 1: Accumulate statistics ===")
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
            
            ngx.say("=== Phase 2: Wait for sliding window to expire ===")
            -- Wait for sliding window to expire (sliding_window_size = 5 seconds)
            ngx.sleep(6)
            
            ngx.say("=== Phase 3: Test after window expiration ===")
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
=== Phase 1: Accumulate statistics ===
Request 1 (200): 200
Request 2 (500): 500
Request 3 (500): 500
Request 4 (should be 502): 502
=== Phase 2: Wait for sliding window to expire ===
=== Phase 3: Test after window expiration ===
Request 5 after expiration (should be 200): 200
Request 6 after expiration (should be 200): 200
--- timeout: 15



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
            
            ngx.say("=== Phase 1: Trigger circuit breaker ===")
            -- First trigger circuit breaker to OPEN state
            local code1 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 1 (500): ", code1)
            
            local code2 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 2 (500): ", code2)
            
            -- Should trigger circuit breaker (2 failures, min_request_threshold=2, error_ratio=1.0 > 0.5)
            local code3 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 3 (should be 502): ", code3)
            
            ngx.say("=== Phase 2: Wait for half-open state ===")
            -- Wait for circuit breaker to enter half-open state
            ngx.sleep(6)
            
            ngx.say("=== Phase 3: Test half-open failure fallback ===")
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
=== Phase 1: Trigger circuit breaker ===
Request 1 (500): 500
Request 2 (500): 500
Request 3 (should be 502): 502
=== Phase 2: Wait for half-open state ===
=== Phase 3: Test half-open failure fallback ===
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
                                "max_breaker_sec": 5,
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "error_ratio": 0.5,
                                    "min_request_threshold": 2,
                                    "sliding_window_size": 60,
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



=== TEST 28: test half-open state request limit enforcement
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            ngx.say("=== Phase 1: Trigger circuit breaker ===")
            -- First trigger circuit breaker to OPEN state
            local code1 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 1 (500): ", code1)
            
            local code2 = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("Request 2 (500): ", code2)
            
            -- Should trigger circuit breaker (2 failures, error_ratio=1.0 > 0.5)
            local code3 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 3 (should be 502): ", code3)
            
            ngx.say("=== Phase 2: Wait for half-open state ===")
            -- Wait for circuit breaker to enter half-open state
            ngx.sleep(6)
            
            ngx.say("=== Phase 3: Test half-open request limit ===")
            -- In half-open state, only half_open_max_calls (2) requests should be allowed
            local code4 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 4 in half-open (1st allowed, should be 200): ", code4)
            
            local code5 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 5 in half-open (2nd allowed, should be 200): ", code5)
            
            -- Third request should be rejected (exceeds half_open_max_calls=2)
            local code6 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 6 in half-open (3rd, should be 502 - exceeds limit): ", code6)
            
            -- Fourth request should also be rejected
            local code7 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 7 in half-open (4th, should be 502 - exceeds limit): ", code7)
            
            ngx.say("=== Phase 4: Verify limit enforcement continues ===")
            -- Even after some time, additional requests should still be rejected in current half-open cycle
            local code8 = t('/api_breaker', ngx.HTTP_GET)
            ngx.say("Request 8 in half-open (should be 502 - exceeds limit): ", code8)
        }
    }
--- request
GET /t
--- response_body
=== Phase 1: Trigger circuit breaker ===
Request 1 (500): 500
Request 2 (500): 500
Request 3 (should be 502): 502
=== Phase 2: Wait for half-open state ===
=== Phase 3: Test half-open request limit ===
Request 4 in half-open (1st allowed, should be 200): 200
Request 5 in half-open (2nd allowed, should be 200): 200
Request 6 in half-open (3rd, should be 502 - exceeds limit): 502
Request 7 in half-open (4th, should be 502 - exceeds limit): 502
=== Phase 4: Verify limit enforcement continues ===
Request 8 in half-open (should be 502 - exceeds limit): 502
--- timeout: 15



=== TEST 22: verify circuit breaker headers persist
--- request
GET /api_breaker
--- error_code: 503
--- response_body
Service temporarily unavailable
--- response_headers
X-Circuit-Breaker: open
Retry-After: 30