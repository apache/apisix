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

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local status_ok_count = 0
            local status_err_count = 0
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                if resp.status == 200 then
                    status_ok_count = status_ok_count + 1
                else
                    status_err_count = status_err_count + 1
                end
            end
            ngx.say(status_ok_count)
            ngx.say(status_err_count)
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({
                conn = 1,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = 'remote_addr',
                policy = "redis",
                redis_host = 'localhost',
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



=== TEST 2: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
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
                        "uri": "/limit_conn"
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
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
10
0



=== TEST 4: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 2,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
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
                        "uri": "/limit_conn"
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



=== TEST 5: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
3
7



=== TEST 6: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
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
                        "uri": "/limit_conn"
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
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
6
4



=== TEST 8: update plugin with username, password
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
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
                        "uri": "/limit_conn"
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



=== TEST 9: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
6
4



=== TEST 10: invalid route: missing redis_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "conn": 1,
                                "policy": "redis"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: then clause did not match"}



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
                        "uri": "/limit_conn"
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
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
10
0



=== TEST 13: set route(key: server_addr)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "server_addr",
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
                        "uri": "/limit_conn"
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



=== TEST 14: key: http_x_real_ip
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "http_x_real_ip",
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
                        "uri": "/limit_conn"
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



=== TEST 15: exceeding the burst (X-Real-IP)
--- config
location /access_root_dir {
    content_by_lua_block {
        local port = ngx.var.server_port
        local httpc = require "resty.http"
        local hc = httpc:new()

        local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
            keepalive = false,
            headers = {["X-Real-IP"] = "10.10.10.1"}
        })
        if res then
            ngx.exit(res.status)
        end
    }
}

location /test_concurrency {
    content_by_lua_block {
        local reqs = {}
        for i = 1, 10 do
            reqs[i] = { "/access_root_dir" }
        end
        local status_ok_count = 0
        local status_err_count = 0
        local resps = { ngx.location.capture_multi(reqs) }
        for i, resp in ipairs(resps) do
            if resp.status == 200 then
                status_ok_count = status_ok_count + 1
            else
                status_err_count = status_err_count + 1
            end
        end
        ngx.say(status_ok_count)
        ngx.say(status_err_count)
    }
}
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
6
4
--- error_log
limit key: 10.10.10.1route



=== TEST 16: key: http_x_forwarded_for
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "http_x_forwarded_for",
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
                        "uri": "/limit_conn"
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



=== TEST 17: exceeding the burst(X-Forwarded-For)
--- config
location /access_root_dir {
    content_by_lua_block {
        local port = ngx.var.server_port
        local httpc = require "resty.http"
        local hc = httpc:new()

        local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
            keepalive = false,
            headers = {["X-Forwarded-For"] = "10.10.10.2"}
        })
        if res then
            ngx.exit(res.status)
        end
    }
}

location /test_concurrency {
    content_by_lua_block {
        local reqs = {}
        for i = 1, 10 do
            reqs[i] = { "/access_root_dir" }
        end
        local status_ok_count = 0
        local status_err_count = 0
        local resps = { ngx.location.capture_multi(reqs) }
        for i, resp in ipairs(resps) do
            if resp.status == 200 then
                status_ok_count = status_ok_count + 1
            else
                status_err_count = status_err_count + 1
            end
        end
        ngx.say(status_ok_count)
        ngx.say(status_err_count)
    }
}
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
6
4
--- error_log
limit key: 10.10.10.2route



=== TEST 18: default rejected_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 4,
                                "burst": 1,
                                "default_conn_delay": 0.1,
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
                        "uri": "/limit_conn"
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



=== TEST 19: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
5
5



=== TEST 20: set global rule with conn = 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 2,
                            "burst": 1,
                            "default_conn_delay": 0.1,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1"
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



=== TEST 21: exceeding the burst of global rule
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
3
7



=== TEST 22: delete global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE
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



=== TEST 23: not exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
5
5
