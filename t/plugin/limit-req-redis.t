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
    my $port = $ENV{TEST_NGINX_SERVER_PORT};

    my $config = $block->config // <<_EOC_;
    location /access_root_dir {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn')
            if res then
                ngx.exit(res.status)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
        require("lib.test_redis").flush_all()
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
});


run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-req")
            local ok, err = plugin.check_schema({
                rate = 1,
                burst = 0,
                rejected_code = 503,
                key = 'remote_addr',
                policy = 'redis',
                redis_host = '127.0.0.1'
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



=== TEST 2: add plugin with redis
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 1,
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
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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



=== TEST 3: not exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]



=== TEST 4: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 200, 200, 503]



=== TEST 5: verify redis connection reused times in debug log
--- log_level: debug
--- pipelined_requests eval
[ "GET /hello", "GET /hello"]
--- error_log_like eval
[qr/redis connection reused times: 0/, qr/redis connection reused times: 1/]



=== TEST 6: update plugin with username password
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_username": "alice",
                            "redis_password": "somepassword"
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
--- request
GET /t
--- response_body
passed



=== TEST 7: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]



=== TEST 8: update plugin with username, wrong password
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_username": "alice",
                            "redis_password": "someerrorpassword"
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
--- request
GET /t
--- response_body
passed



=== TEST 9: catch wrong pass
--- request
GET /hello
--- error_code: 500
--- error_log
failed to limit req: WRONGPASS invalid username-password pair or user is disabled.



=== TEST 10: invalid route: missing redis_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
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
{"error_msg":"failed to check the configuration of plugin limit-req err: then clause did not match"}



=== TEST 11: disable plugin
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
                        "uri": "/hello"
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



=== TEST 12: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]



=== TEST 13: set route (key: server_addr)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 2,
                            "rejected_code": 503,
                            "key": "server_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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



=== TEST 14: default rejected_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 2,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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



=== TEST 15: consumer binds the limit-req plugin and `key` is `consumer_name`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "new_consumer",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "limit-req": {
                            "rate": 3,
                            "burst": 2,
                            "rejected_code": 403,
                            "key": "consumer_name",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
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



=== TEST 16: route add "key-auth" plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "key-auth": {}
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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



=== TEST 17: not exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-jack
--- error_code eval
[200, 200, 200]



=== TEST 18: update the limit-req plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "new_consumer",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 403,
                            "key": "consumer_name",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 19: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-jack
--- error_code eval
[200, 403, 403, 403]



=== TEST 20: key is consumer_name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 2,
                            "burst": 1,
                            "key": "consumer_name",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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



=== TEST 21: get "consumer_name" is empty
--- request
GET /hello
--- response_body
hello world
--- error_log
The value of the configured key is empty, use client IP instead



=== TEST 22: delete consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/new_consumer', ngx.HTTP_DELETE)

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 23: delete route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

            ngx.status =code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 24: check_schema failed (the `rate` attribute is equal to 0)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-req")
            local ok, err = plugin.check_schema({rate = 0, burst = 0, rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body eval
qr/property \"rate\" validation failed: expected 0 to be greater than 0/



=== TEST 25: set route for hash-tag key-format tests (rate=100, burst=0)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 100,
                            "burst": 0,
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
--- request
GET /t
--- response_body
passed



=== TEST 26: atomic script stores keys with hash-tag format
--- config
    location /t {
        content_by_lua_block {
            -- Flush all Redis state so this test starts clean.
            local redis = require "resty.redis"
            local red = redis:new()
            red:set_timeout(1000)
            local ok, err = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            local ok_flush, err_flush = red:flushall()
            if not ok_flush then
                ngx.say("flushall failed: ", err_flush)
                return
            end

            -- Make one request to trigger the atomic script.
            local httpc = require "resty.http"
            local hc = httpc:new()
            local port = ngx.var.server_port
            local res, err2 = hc:request_uri("http://127.0.0.1:" .. port .. "/hello")
            if not res then
                ngx.say("request failed: ", err2)
                return
            end
            ngx.say("status: ", res.status)

            -- Verify the keys use the hash-tag format {limit_req:...}suffix.
            local keys, err3 = red:keys("{limit_req:*}*")
            if not keys then
                ngx.say("keys cmd failed: ", err3)
                return
            end
            ngx.say("hash-tag keys found: ", #keys >= 2 and "yes" or "no (" .. #keys .. ")")
        }
    }
--- request
GET /t
--- response_body
status: 200
hash-tag keys found: yes
--- no_error_log
[error]



=== TEST 27: set route for first-request tests (rate=1, burst=0)
--- config
    location /t {
        content_by_lua_block {
            -- Flush so no stale excess remains from previous tests.
            local redis = require "resty.redis"
            local red = redis:new()
            red:set_timeout(1000)
            local ok, err = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            local ok_flush, err_flush = red:flushall()
            if not ok_flush then
                ngx.say("flushall failed: ", err_flush)
                return
            end

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 1,
                            "burst": 0,
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
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say("route update failed: ", body)
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 28: first request is always admitted even when burst=0 (no prior state)
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, 503]



=== TEST 29: set route for atomic-script concurrency tests (rate=1, burst=0)
--- config
    location /t {
        content_by_lua_block {
            -- Flush so no stale excess remains from previous tests.
            local redis = require "resty.redis"
            local red = redis:new()
            red:set_timeout(1000)
            local ok, err = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            local ok_flush, err_flush = red:flushall()
            if not ok_flush then
                ngx.say("flushall failed: ", err_flush)
                return
            end

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 1,
                            "burst": 0,
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
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say("route update failed: ", body)
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 30: atomic script prevents concurrent requests from bypassing rate limit
--- config
    location /hello_proxy {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()
            local port = ngx.var.server_port
            local res, err = hc:request_uri("http://127.0.0.1:" .. port .. "/hello")
            if not res then
                ngx.exit(500)
            end
            ngx.exit(res.status)
        }
    }

    location /t {
        content_by_lua_block {
            -- Fire 5 concurrent sub-requests via capture_multi.
            -- Each sub-request calls /hello through a separate resty.http connection,
            -- so the atomic Redis Lua script is exercised under concurrent load.
            -- With rate=1, burst=0 and a clean Redis state, exactly 1 request
            -- should pass (status 200) and the remaining 4 should be rejected (503).
            local reqs = {}
            for i = 1, 5 do
                reqs[i] = { "/hello_proxy" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            local ok_count = 0
            local reject_count = 0
            for _, resp in ipairs(resps) do
                if resp.status == 200 then
                    ok_count = ok_count + 1
                elseif resp.status == 503 then
                    reject_count = reject_count + 1
                end
            end
            ngx.say("admitted: ", ok_count)
            ngx.say("rejected: ", reject_count)
        }
    }
--- request
GET /t
--- response_body
admitted: 1
rejected: 4
--- no_error_log
[error]
