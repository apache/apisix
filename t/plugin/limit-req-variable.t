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

repeat_each(1);
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

=== TEST 1: use variable in rate and burst with default value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rate": "${http_rate ?? 10}",
                                "burst": "${http_burst ?? 2}",
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "policy": "local"
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



=== TEST 2: request without rate/burst headers - uses default values
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 503, 503, 503]
--- error_log
limit req rate: 10, burst: 2



=== TEST 3: request with rate header
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local run_tests = function()
                for i = 1, 5, 1 do
                    local res = httpc:request_uri(uri, {
                        method = "GET",
                        headers = { ["rate"] = "2" }
                    })
                    if res.status ~= 200 then
                        ngx.say(i .. "th request should return 200, but got " .. res.status)
                        return
                    end
                end
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["rate"] = "2" }
                })
                if res.status ~= 503 then
                    ngx.say("6th request should return 503, but got " .. res.status)
                    return
                end
            end

            run_tests()
            ngx.sleep(1)
            run_tests()

            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
passed
--- error_log
limit req rate: 2, burst: 2



=== TEST 4: request with rate and burst header
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local run_tests = function()
                for i = 1, 6, 1 do
                    local res = httpc:request_uri(uri, {
                        method = "GET",
                        headers = { ["rate"] = "3", ["burst"] = "4" }
                    })
                    if res.status ~= 200 then
                        ngx.say(i .. "th request should return 200, but got " .. res.status)
                        return
                    end
                end
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["rate"] = "3", ["burst"] = "4" }
                })
                if res.status ~= 503 then
                    ngx.say("7th request should return 503, but got " .. res.status)
                    return
                end
            end

            run_tests()
            ngx.sleep(1)
            run_tests()

            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
passed
--- error_log
limit req rate: 3, burst: 4



=== TEST 5: schema check with both rate/burst and rules should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rate": 10,
                                "burst": 2,
                                "key": "remote_addr",
                                "rules": [
                                    {
                                        "rate": 5,
                                        "burst": 1,
                                        "key": "remote_addr"
                                    }
                                ]
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
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-req err: value should match only one schema, but matches both schemas 1 and 2"}



=== TEST 6: duplicate keys in rules should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 5,
                                        "burst": 1,
                                        "key": "${http_user}"
                                    },
                                    {
                                        "rate": 10,
                                        "burst": 2,
                                        "key": "${http_user}"
                                    }
                                ]
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
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-req err: duplicate key '${http_user}' in rules"}



=== TEST 7: setup route with multi-level rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 10,
                                        "burst": 2,
                                        "key": "${http_user}"
                                    },
                                    {
                                        "rate": 5,
                                        "burst": 1,
                                        "key": "${http_project}"
                                    }
                                ],
                                "rejected_code": 503,
                                "rejected_msg": "rate limited"
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



=== TEST 8: no rule matches - returns 500
--- request
GET /hello
--- error_code: 500
--- error_log
failed to get limit req rules



=== TEST 9: match user rule - rate limiting applies
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 12, 1 do
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["user"] = "jack" }
                })
                if i <= 12 and res.status ~= 200 then
                    ngx.say(i .. "th request should return 200, but got " .. res.status)
                    return
                end
            end

            local res = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["user"] = "jack" }
            })
            if res.status ~= 503 then
                ngx.say("13th request should return 503, but got " .. res.status)
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



=== TEST 10: match project rule - rate limiting applies
--- setup
    ngx.sleep(1)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 6, 1 do
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["project"] = "apisix" }
                })
                if res.status ~= 200 then
                    ngx.say(i .. "th request should return 200, but got " .. res.status)
                    return
                end
            end

            local res = httpc:request_uri(uri, {
                method = "GET",
                headers = { ["project"] = "apisix" }
            })
            if res.status ~= 503 then
                ngx.say("7th request should return 503, but got " .. res.status)
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



=== TEST 11: rules with variables with default values
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": "${http_rate ?? 5}",
                                        "burst": "${http_burst ?? 1}",
                                        "key": "${remote_addr}"
                                    }
                                ],
                                "rejected_code": 503,
                                "rejected_msg": "rate limited"
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



=== TEST 12: rules with variables in rate - default value
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200, 200, 200, 503]
--- response_body eval
["hello world\n", "hello world\n", "hello world\n", "hello world\n", "hello world\n", "hello world\n", "{\"error_msg\":\"rate limited\"}\n"]



=== TEST 13: rules with variables in rate - with header
--- setup
    ngx.sleep(2)
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
rate: 2
--- error_code eval
[200, 200, 200, 503]
--- response_body eval
["hello world\n", "hello world\n", "hello world\n", "{\"error_msg\":\"rate limited\"}\n"]



=== TEST 14: rules with different time windows
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 2,
                                        "burst": 0,
                                        "key": "${remote_addr}_short"
                                    },
                                    {
                                        "rate": 3,
                                        "burst": 1,
                                        "key": "${remote_addr}_long"
                                    }
                                ],
                                "rejected_code": 503,
                                "rejected_msg": "rate limited"
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



=== TEST 15: test rules with different rate limits
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 2, 1 do
                local res = httpc:request_uri(uri)
                if res.status ~= 200 then
                    ngx.say("first two requests failed, status: " .. res.status)
                    return
                end
            end

            -- req 3, rejected by rule 1 (rate: 2, burst: 0)
            local res = httpc:request_uri(uri)
            if res.status ~= 503 then
                ngx.say("req 3 should be rejected by rule 1, but got status: ", res.status)
                return
            end

            ngx.sleep(1)

            -- req 4, after sleep should pass rule 1 but might hit rule 2
            res = httpc:request_uri(uri)
            if res.status ~= 200 then
                ngx.say("req 4 failed, status: ", res.status)
                return
            end

            -- req 5, rejected by rule 2
            res = httpc:request_uri(uri)
            if res.status ~= 503 then
                ngx.say("req 5 should be rejected by rule 2, but got status: ", res.status)
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



=== TEST 16: legacy mode with string rate and burst
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rate": "100",
                                "burst": "10",
                                "key": "remote_addr",
                                "policy": "local"
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



=== TEST 17: multi-rule mode with redis policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 100,
                                        "burst": 20,
                                        "key": "remote_addr"
                                    },
                                    {
                                        "rate": "$http_x_user_id",
                                        "burst": 50,
                                        "key": "http_x_user_id"
                                    }
                                ],
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6379,
                                "rejected_code": 429
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
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- skip_eval
3: no -r system('redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1')
--- response_body
passed



=== TEST 18: allow_degradation when rules fail to resolve
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": "$http_nonexistent_var",
                                        "burst": 10,
                                        "key": "${http_nonexistent_key}"
                                    }
                                ],
                                "rejected_code": 503,
                                "allow_degradation": true
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



=== TEST 19: request with allow_degradation - passes through
--- request
GET /hello
--- error_code: 200
--- response_body
hello world
--- error_log
failed to get limit req rules



=== TEST 20: nodelay option in multi-rule mode
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 2,
                                        "burst": 5,
                                        "key": "remote_addr"
                                    }
                                ],
                                "nodelay": true,
                                "rejected_code": 503
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



=== TEST 21: nodelay - requests should not be delayed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local start_time = ngx.now()
            for i = 1, 7, 1 do
                local res = httpc:request_uri(uri)
                if res.status ~= 200 then
                    ngx.say(i .. "th request should return 200, but got " .. res.status)
                    return
                end
            end
            local elapsed = ngx.now() - start_time

            -- with nodelay=true, 7 requests should complete quickly (< 0.5s)
            if elapsed > 0.5 then
                ngx.say("requests took too long: " .. elapsed .. "s")
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
