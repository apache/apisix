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
run_tests;

__DATA__

=== TEST 1: set route, missing redis host
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
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis"
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: failed to validate dependent schema for \"policy\": value should match only one schema, but matches none"}
--- no_error_log
[error]



=== TEST 2: set route, with redis host and port
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
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_timeout": 1001
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: set route(default value: port and timeout)
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
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr",
                                    "policy": "redis",
                                    "redis_host": "127.0.0.1",
                                    "redis_port": 6379,
                                    "redis_timeout": 1000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 4: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]
--- no_error_log
[error]



=== TEST 5: up the limit
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 503, 404, 503, 503]
--- no_error_log
[error]



=== TEST 6: set route, with redis host, port and right password
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- set redis password
            local redis = require "resty.redis"

            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            -- for get_reused_times works
            -- local ok, err = red:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            local count
            count, err = red:get_reused_times()
            if 0 == count then
                local res, err = red:eval([[
                    local key = 'requirepass'
                    local value = "foobared"
                    -- redis.replicate_commands()
                    local val = redis.pcall('CONFIG', 'SET', key, value)
                    return val
                    ]], 0)
                --
                if not res then
                    ngx.say("failed to set: ", err)
                    return
                end
            elseif err then
                -- ngx.say("already set requirepass done: ", err)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_timeout": 1001,
                            "redis_password": "foobared"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]
--- no_error_log
[error]



=== TEST 8: up the limit
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 503, 404, 503, 503]
--- no_error_log
[error]



=== TEST 9: set route, with redis host, port and wrong password
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
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_timeout": 1001,
                            "redis_password": "WRONG_foobared"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello_new"
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
--- error_code eval
200
--- no_error_log
[error]



=== TEST 10: request for TEST 9
--- request
GET /hello_new
--- error_code eval
500
--- response_body
{"error_msg":"failed to limit count: ERR invalid password"}
--- error_log
failed to limit req: ERR invalid password



=== TEST 11: multi request for TEST 9
--- pipelined_requests eval
["GET /hello_new", "GET /hello1", "GET /hello1", "GET /hello_new"]
--- error_code eval
[500, 404, 404, 500]



=== TEST 12: restore redis password to ''
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- set redis password
            local redis = require "resty.redis"

            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            -- for get_reused_times works
            -- local ok, err = red:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            local count
            count, err = red:get_reused_times()
            if 0 == count then
                local redis_password = "foobared"
                if redis_password and redis_password ~= '' then
                    local ok, err = red:auth(redis_password)
                    if not ok then
                        return nil, err
                    end
                end
                local res, err = red:eval([[
                    local key = 'requirepass'
                    local value = ''
                    -- redis.replicate_commands()
                    local val = redis.pcall('CONFIG', 'SET', key, value)
                    return val
                    ]], 0)
                --
                if not res then
                    ngx.say("failed to set: ", err)
                    return
                end
            elseif err then
                -- ngx.say("already set requirepass done: ", err)
                return
            end
        }
    }
--- request
GET /t
--- error_code eval
200
--- no_error_log
[error]
