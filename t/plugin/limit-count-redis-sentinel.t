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

=== TEST 1: set route without redis master name
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26379}
                             ],
                             "redis_role": "master"
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
--- error_code: 400



=== TEST 2: set route without redis sentinels
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_role": "master",
                            "redis_database": 1
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
--- error_code: 400



=== TEST 3: set route
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                {"host": "127.0.0.1", "port": 26379}
                            ],
                            "redis_username": "master",
                            "redis_password": "master-password",
                            "redis_master_name": "mymaster",
                            "redis_role": "master"
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



=== TEST 4: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 5: set route with different limit count
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26379}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master",
                             "redis_database": 1
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
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello1",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26379}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master",
                             "redis_database": 1
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



=== TEST 6: up the limit
--- pipelined_requests eval
["GET /hello","GET /hello", "GET /hello", "GET /hello1", "GET /hello1"]
--- error_code eval
[200, 200, 503, 200, 503]



=== TEST 7: set route with authenticated redis sentinel without password
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26380}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master",
                             "redis_database": 1
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



=== TEST 8: up the limit
--- request
GET /hello
--- error_code: 500
--- error_log
redis connection failed, err: NOAUTH Authentication required



=== TEST 9: set route with authenticated redis sentinel with password
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26380}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master",
                             "redis_database": 1,
                             "sentinel_username": "admin",
                             "sentinel_password": "admin-password"
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
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello1",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 26380}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master",
                             "redis_database": 1,
                             "sentinel_username": "admin",
                             "sentinel_password": "admin-password"
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



=== TEST 10: up the limit
--- pipelined_requests eval
["GET /hello","GET /hello", "GET /hello", "GET /hello1", "GET /hello1"]
--- error_code eval
[200, 200, 503, 200, 503]



=== TEST 11: create a limit-count with broken redis sentinels
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                 {"host": "127.0.0.1", "port": 503},
                                 {"host": "127.0.0.2", "port": 503}
                             ],
                             "redis_master_name": "mymaster",
                             "redis_role": "master"
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



=== TEST 12: send test request
--- request
GET /hello
--- error_code: 500
--- error_log
failed to limit count: redis connection failed, err: no hosts available, previous_errors: connection refused, connection refused



=== TEST 13: set route with invalid username:password
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
                            "time_window": 2,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-sentinel",
                            "redis_sentinels": [
                                {"host": "127.0.0.1", "port": 26379}
                            ],
                            "redis_username": "invalid",
                            "redis_password": "invalid",
                            "redis_master_name": "mymaster",
                            "redis_role": "master"
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



=== TEST 14: redis authentication failure
--- request
GET /hello
--- error_code: 500
--- error_log
invalid username-password pair



=== TEST 15: routes with different databases must not share connections
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i, db in ipairs({1, 2}) do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    string.format([[{
                        "uri": "/hello%s",
                        "plugins": {
                            "limit-count": {
                                "count": 5,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "policy": "redis-sentinel",
                                "redis_sentinels": [
                                     {"host": "127.0.0.1", "port": 26379}
                                 ],
                                 "redis_master_name": "mymaster",
                                 "redis_role": "master",
                                 "redis_database": %d
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    }]], i == 1 and "" or "1", db)
                    )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end

            ngx.sleep(0.5)

            -- alternate requests between the two routes so that the second
            -- route is served by a connection put into the keepalive pool
            -- by the first one if the pool is wrongly shared
            local http = require "resty.http"
            local uris = {
                "http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1",
            }
            for i = 1, 2 do
                for _, uri in ipairs(uris) do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    if not res then
                        ngx.say("request failed: ", err)
                        return
                    end
                    ngx.say(res.status, " remaining: ",
                            res.headers["X-RateLimit-Remaining"] or "nil")
                end
            end

            -- each database must contain only its own route's counter,
            -- tracking exactly the 2 requests sent to that route
            local redis = require "resty.redis"
            for db = 1, 2 do
                local red = redis:new()
                red:set_timeout(1000)
                local ok, err = red:connect("127.0.0.1", 6479)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end
                ok, err = red:select(db)
                if not ok then
                    ngx.say("failed to select db ", db, ": ", err)
                    return
                end
                local keys, err = red:keys("plugin-limit-count*")
                if not keys then
                    ngx.say("failed to get keys: ", err)
                    return
                end
                ngx.say("db ", db, " keys: ", #keys)
                for _, key in ipairs(keys) do
                    local counter, err = red:get(key)
                    if err then
                        ngx.say("failed to get counter of ", key, ": ", err)
                        return
                    end
                    ngx.say("db ", db, " counter: ", counter)
                    red:del(key)
                end
                red:close()
            end

            for i = 1, 2 do
                t('/apisix/admin/routes/' .. i, ngx.HTTP_DELETE)
            end
        }
    }
--- timeout: 10
--- response_body
200 remaining: 4
200 remaining: 4
200 remaining: 3
200 remaining: 3
db 1 keys: 1
db 1 counter: 2
db 2 keys: 1
db 2 counter: 2
