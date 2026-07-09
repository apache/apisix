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

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
        require("lib.test_redis").flush_all({password = "foobared"})
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
});

run_tests;

__DATA__

=== TEST 1: routes pointing to the same redis but different databases must not share connections
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
                            "count": 5,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 1,
                            "redis_keepalive_pool": 1
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
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello1",
                    "plugins": {
                        "limit-count": {
                            "count": 5,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 2,
                            "redis_keepalive_pool": 1
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
                ngx.say(body)
                return
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
                            res.headers["X-RateLimit-Remaining"])
                end
            end

            -- each database must contain only its own route's counter,
            -- tracking exactly the 2 requests sent to that route
            local redis = require "resty.redis"
            for db = 1, 2 do
                local red = redis:new()
                red:set_timeout(1000)
                local ok, err = red:connect("127.0.0.1", 6379)
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
                end
                red:close()
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



=== TEST 2: a route with wrong credentials must not reuse another route's authenticated connections
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- the CI redis has a user alice with the same permissions
            -- as the default user; route 2 uses a wrong password, so it can
            -- only ever succeed by wrongly reusing route 1's authenticated
            -- connection from a shared keepalive pool
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 5,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_username": "alice",
                            "redis_password": "somepassword",
                            "redis_keepalive_pool": 1
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
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello1",
                    "plugins": {
                        "limit-count": {
                            "count": 5,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_username": "alice",
                            "redis_password": "wrongpassword",
                            "redis_keepalive_pool": 1
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
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

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
        }
    }
--- timeout: 10
--- response_body
200 remaining: 4
500 remaining: nil
200 remaining: 3
500 remaining: nil
--- error_log
failed to limit count



=== TEST 3: clean up the routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say(code)
            code = t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            ngx.say(code)
        }
    }
--- response_body
200
200
