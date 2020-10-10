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
                unhealthy_response_code = 502,
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



=== TEST 2: default http_statuses
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.api-breaker")
            local ok, err = plugin.check_schema({
                unhealthy_response_code = 502,
                unhealthy = {
                    failures = 1,
                },
                healthy = {
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



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "unhealthy_response_code": 502,
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



=== TEST 4: trigger breaker
--- request eval
["GET /api_breaker?code=200", "GET /api_breaker?code=500", "GET /api_breaker?code=503", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500"]
--- error_code eval
[200, 500, 503, 500, 502, 502]
--- no_error_log
[error]



=== TEST 5: trigger reset status
--- request eval
["GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=200", "GET /api_breaker?code=200", "GET /api_breaker?code=200", "GET /api_breaker?code=500", "GET /api_breaker?code=500"]
--- error_code eval
[500, 500, 200, 200, 200, 500, 500]
--- no_error_log
[error]



=== TEST 6: trigger del healthy numeration
--- request eval
["GET /api_breaker?code=500", "GET /api_breaker?code=200", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500"]
--- error_code eval
[500, 200, 500, 500, 502, 502, 502]
--- no_error_log
[error]



=== TEST 7: add plugin with default config value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "unhealthy_response_code": 502,
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



=== TEST 8: default value
--- request
GET /api_breaker?code=500
--- error_code: 500
--- no_error_log
[error]



=== TEST 9: trigger default value of unhealthy.http_statuses breaker 
--- request eval
["GET /api_breaker?code=200", "GET /api_breaker?code=500", "GET /api_breaker?code=503", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500"]
--- error_code eval
[200, 500, 503, 500, 500, 502]
--- no_error_log
[error]



=== TEST 10: trigger timeout 2 second
--- config
    location /sleep1 {
        proxy_pass "http://127.0.0.1:1980/sleep1";
    }
--- request eval
["GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=200", "GET /sleep1", "GET /sleep1", "GET /sleep1", "GET /api_breaker?code=200", "GET /api_breaker?code=200", "GET /api_breaker?code=200", "GET /api_breaker?code=200","GET /api_breaker?code=200"]
--- error_code eval
[500, 500, 500, 502, 200, 200, 200, 200, 200, 200, 200,200]
--- no_error_log
[error]
--- timeout: 100


=== TEST 11: trigger timeout again 4 second
--- config
    location /sleep1 {
        proxy_pass "http://127.0.0.1:1980/sleep1";
    }
--- request eval
["GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=500", "GET /api_breaker?code=200", "GET /sleep1", "GET /sleep1", "GET /sleep1", "GET /api_breaker?code=500","GET /api_breaker?code=500","GET /api_breaker?code=500","GET /api_breaker?code=500"]
--- error_code eval
[500, 500, 500, 502, 200, 200, 200, 500,502,502,502]
--- no_error_log
[error]
--- timeout: 100


=== TEST 12: del plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
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
--- timeout: 100



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
                            "unhealthy_response_code": 502,
                            "max_breaker_seconds": 10,
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



=== TEST 14: max_breaker_seconds
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('GET http://127.0.0.1:1980/mysleep?seconds=10')

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code
200
--- no_error_log
[error]
--- timeout: 100