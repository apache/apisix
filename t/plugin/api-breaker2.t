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
                    permitted_number_of_calls_in_half_open_state = 3
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
{"break_response_code":502,"healthy":{"http_statuses":[200],"success_ratio":0.6},"max_breaker_sec":300,"policy":"unhealthy-ratio","unhealthy":{"error_ratio":0.5,"http_statuses":[500],"min_request_threshold":10,"permitted_number_of_calls_in_half_open_state":3,"sliding_window_size":300}}



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



=== TEST 9: bad permitted_number_of_calls_in_half_open_state (too large)
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
                                "permitted_number_of_calls_in_half_open_state": 25
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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"unhealthy\" validation failed: property \"permitted_number_of_calls_in_half_open_state\" validation failed: expected 25 to be at most 20"}



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
                                    "permitted_number_of_calls_in_half_open_state": 2
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



=== TEST $((${1}+1)): hit route (return 200)
--- request
GET /api_breaker
--- response_body
hello world



=== TEST $((${1}+1)): hit route and return 500 (first failure)
--- request
GET /api_breaker?code=500
--- error_code: 500
--- response_body
fault injection!



=== TEST $((${1}+1)): hit route and return 500 (second failure)
--- request
GET /api_breaker?code=500
--- error_code: 500
--- response_body
fault injection!



=== TEST $((${1}+1)): hit route and return 500 (third failure, should trigger circuit breaker)
--- request
GET /api_breaker?code=500
--- error_code: 502
--- response_body
Upstream failure



=== TEST $((${1}+1)): hit route (circuit breaker should be open)
--- request
GET /api_breaker
--- error_code: 502
--- response_body
Upstream failure



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



=== TEST 16: hit route in half-open state (should allow limited requests)
--- request
GET /api_breaker
--- response_body
hello world



=== TEST 17: hit route again in half-open state (should allow second request)
--- request
GET /api_breaker
--- response_body
hello world



=== TEST 18: circuit breaker should close after successful requests
--- request
GET /api_breaker
--- response_body
hello world



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



=== TEST 22: verify circuit breaker headers persist
--- request
GET /api_breaker
--- error_code: 503
--- response_body
Service temporarily unavailable
--- response_headers
X-Circuit-Breaker: open
Retry-After: 30