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

=== TEST 1: set route, counter will be shared
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
                            "count": 1,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 1,
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
--- response_body
passed



=== TEST 2: test X-RateLimit-Reset second number could be decline
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local old_X_RateLimit_Reset = 61
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.sleep(2)
                if tonumber(res.headers["X-RateLimit-Reset"]) < old_X_RateLimit_Reset then
                    old_X_RateLimit_Reset = tonumber(res.headers["X-RateLimit-Reset"])
                    ngx.say("OK")
                else
                   ngx.say("WRONG")
                end
            end
            ngx.say("Done")
        }
    }
--- response_body
OK
OK
Done



=== TEST 3: set router
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
                            "time_window": 10,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 1,
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
--- response_body
passed



=== TEST 4: test header X-RateLimit-Remaining exist when limit rejected
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.sleep(1)
                table.insert(ress, res.headers["X-RateLimit-Remaining"])

            end
            ngx.say(json.encode(ress))
        }
    }
--- response_body
["1","0","0"]



=== TEST 5: set route, with redis host, port and SSL
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
                            "redis_port": 6380,
                            "redis_timeout": 1001,
                            "redis_ssl": true,
                            "redis_ssl_verify": false
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
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 7: up the limit
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 503, 404, 503, 503]



=== TEST 8: set route, with redis host, port, SSL and SSL verify is true(will cause ssl handshake err), with enable degradation switch
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
                            "allow_degradation": true,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6380,
                            "redis_timeout": 1001,
                            "redis_ssl": true,
                            "redis_ssl_verify": true
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



=== TEST 9: enable degradation switch for TEST 8
--- request
GET /hello
--- response_body
hello world
--- error_log
failed to do ssl handshake



=== TEST 10: set router
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
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 1,
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
--- response_body
passed



=== TEST 11: test header X-RateLimit-Reset shouldn't be set to 0 after request be rejected
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.sleep(1)
                local reset = res.headers["X-RateLimit-Reset"]
                if tonumber(reset) <= 0 then
                    ngx.say("failed")
                end

            end
            ngx.say("success")
        }
    }
--- response_body
success
