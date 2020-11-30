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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local ok, err = plugin.check_schema({
                break_response_code = 502,
                unhealthy = {
                    http_statuses = {500},
                    failures = 1,
                },
                healthy = {
                    http_statuses = {200},
                    successes = 1,
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
--- no_error_log
[error]



=== TEST 2: default configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local conf = {
                break_response_code = 502
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
{"break_response_code":502,"healthy":{"http_statuses":[200],"successes":3},"max_breaker_sec":300,"unhealthy":{"failures":3,"http_statuses":[500]}}
--- no_error_log
[error]



=== TEST 3: default `healthy`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local conf = {
                break_response_code = 502,
                healthy = {}
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
{"break_response_code":502,"healthy":{"http_statuses":[200],"successes":3},"max_breaker_sec":300,"unhealthy":{"failures":3,"http_statuses":[500]}}
--- no_error_log
[error]



=== TEST 4: default `unhealthy`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local conf = {
                break_response_code = 502,
                unhealthy = {}
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
{"break_response_code":502,"healthy":{"http_statuses":[200],"successes":3},"max_breaker_sec":300,"unhealthy":{"failures":3,"http_statuses":[500]}}
--- no_error_log
[error]



=== TEST 5: bad break_response_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 199,
                            "unhealthy": {
                                "http_statuses": [500, 503],
                                "failures": 3
                            },
                            "healthy": {
                                "http_statuses": [200, 206],
                                "successes": 3
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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"break_response_code\" validation failed: expected 199 to be greater than 200"}
--- no_error_log
[error]



=== TEST 6: bad max_breaker_sec
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 200,
                            "max_breaker_sec": -1
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
--- error_code: 400
--- no_error_log
[error]



=== TEST 7: bad unhealthy.http_statuses
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 200,
                            "max_breaker_sec": 40,
                            "unhealthy": {
                                "http_statuses": [500, 603],
                                "failures": 3
                            },
                            "healthy": {
                                "http_statuses": [200, 206],
                                "successes": 3
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
--- error_code: 400
--- no_error_log
[error]



=== TEST 8: same http_statuses in healthy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 500,
                            "unhealthy": {
                                "http_statuses": [500, 503],
                                "failures": 3
                            },
                            "healthy": {
                                "http_statuses": [206, 206],
                                "successes": 3
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
{"error_msg":"failed to check the configuration of plugin api-breaker err: property \"healthy\" validation failed: property \"http_statuses\" validation failed: expected unique items but items 1 and 2 are equal"}
--- no_error_log
[error]



=== TEST 9: set route, http_statuses: [500, 503]
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 599,
                            "unhealthy": {
                                "http_statuses": [500, 503],
                                "failures": 3
                            },
                            "healthy": {
                                "http_statuses": [200, 206],
                                "successes": 3
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
--- no_error_log
[error]



=== TEST 10: trigger breaker
--- request eval
[
    "GET /api_breaker?code=200", "GET /api_breaker?code=500",
    "GET /api_breaker?code=503", "GET /api_breaker?code=500",
    "GET /api_breaker?code=500", "GET /api_breaker?code=500"
]
--- error_code eval
[200, 500, 503, 500, 599, 599]
--- no_error_log
[error]



=== TEST 11: trigger reset status
--- request eval
[
    "GET /api_breaker?code=500", "GET /api_breaker?code=500",

    "GET /api_breaker?code=200", "GET /api_breaker?code=200",
    "GET /api_breaker?code=200",

    "GET /api_breaker?code=500", "GET /api_breaker?code=500"
]
--- error_code eval
[
    500, 500,
    200, 200, 200,
    500, 500
]
--- no_error_log
[error]



=== TEST 12: trigger del healthy numeration
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("toolkit.json")

        -- trigger to unhealth
        for i = 1, 4 do
            local code = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("code: ", code)
        end

        -- break for 3 seconds
        ngx.sleep(3)

        -- make a try
        for i = 1, 4 do
            local code = t('/api_breaker?code=200', ngx.HTTP_GET)
            ngx.say("code: ", code)
        end

        for i = 1, 4 do
            local code = t('/api_breaker?code=500', ngx.HTTP_GET)
            ngx.say("code: ", code)
        end
    }
}
--- request
GET /t
--- response_body
code: 500
code: 500
code: 500
code: 599
code: 200
code: 200
code: 200
code: 200
code: 500
code: 500
code: 500
code: 599
--- no_error_log
[error]
breaker_time: 4
--- error_log
breaker_time: 2



=== TEST 13: add plugin with default config value
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
                            "unhealthy": {
                                "failures": 3
                            },
                            "healthy": {
                                "successes": 3
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
--- no_error_log
[error]



=== TEST 14: default value
--- request
GET /api_breaker?code=500
--- error_code: 500
--- no_error_log
[error]



=== TEST 15: trigger default value of unhealthy.http_statuses breaker
--- request eval
[
    "GET /api_breaker?code=200", "GET /api_breaker?code=500",
    "GET /api_breaker?code=503", "GET /api_breaker?code=500",
    "GET /api_breaker?code=500", "GET /api_breaker?code=500"
]
--- error_code eval
[200, 500, 503, 500, 500, 502]
--- no_error_log
[error]



=== TEST 16: unhealthy -> timeout -> normal
--- config
    location /sleep1 {
        proxy_pass "http://127.0.0.1:1980/sleep1";
    }
--- request eval
[
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=500",
    "GET /api_breaker?code=200",

    "GET /sleep1",
    "GET /sleep1",
    "GET /sleep1",

    "GET /api_breaker?code=200",
    "GET /api_breaker?code=200",
    "GET /api_breaker?code=200",
    "GET /api_breaker?code=200",
    "GET /api_breaker?code=200"]
--- error_code eval
[
    500, 500, 500, 502,
    200, 200, 200,
    200, 200, 200, 200,200
]
--- no_error_log
[error]



=== TEST 17: unhealthy -> timeout -> unhealthy
--- config
location /sleep1 {
    proxy_pass "http://127.0.0.1:1980/sleep1";
}
--- request eval
[
    "GET /api_breaker?code=500", "GET /api_breaker?code=500",
    "GET /api_breaker?code=500", "GET /api_breaker?code=200",

    "GET /sleep1", "GET /sleep1", "GET /sleep1",

    "GET /api_breaker?code=500","GET /api_breaker?code=500",
    "GET /api_breaker?code=500","GET /api_breaker?code=500"
    ]
--- error_code eval
[
    500, 500, 500, 502,
    200, 200, 200,
    500,502,502,502
]
--- no_error_log
[error]



=== TEST 18: enable plugin, unhealthy.failures=1
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
                            "max_breaker_sec": 10,
                            "unhealthy": {
                                "http_statuses": [500, 503],
                                "failures": 1
                            },
                            "healthy": {
                                "successes": 3
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
--- no_error_log
[error]



=== TEST 19: hit route 20 times, confirm the breaker time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local status_count = {}
            for i = 1, 20 do
                local code = t('/api_breaker?code=500', ngx.HTTP_GET)
                code = tostring(code)
                status_count[code] = (status_count[code] or 0) + 1
                ngx.sleep(1)
            end

            ngx.say(json.encode(status_count))
        }
    }
--- request
GET /t
--- no_error_log
[error]
phase_func(): breaker_time: 16
--- error_log
phase_func(): breaker_time: 2
phase_func(): breaker_time: 4
phase_func(): breaker_time: 8
phase_func(): breaker_time: 10
--- response_body
{"500":4,"502":16}
--- timeout: 25
