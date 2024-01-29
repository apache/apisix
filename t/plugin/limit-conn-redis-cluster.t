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
                counter_type = "redis-cluster",
                redis_cluster_nodes = {
                    "127.0.0.1:5000",
                    "127.0.0.1:5003",
                    "127.0.0.1:5002"
                },
                dict_name = "test",
                redis_cluster_name = "test"
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
                                "counter_type": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5003",
                                    "127.0.0.1:5002"
                                ],
                                "redis_cluster_name": "test"
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
                                "counter_type": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5002"
                                ],
                                "redis_prefix": "test",
                                "redis_cluster_name": "redis-cluster-1"
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
                                "counter_type": "redis-cluster",
                                "redis_prefix": "test",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5002"
                                ],
                                "redis_cluster_name": "redis-cluster-1"
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



=== TEST 8: set route, with redis_cluster_nodes and redis_cluster_name redis_cluster_ssl and redis_cluster_ssl_verify
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
                                "counter_type": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:7001",
                                    "127.0.0.1:7002",
                                    "127.0.0.1:7000"
                                ],
                                "redis_prefix": "test",
                                "redis_cluster_name": "redis-cluster-2",
                                "redis_cluster_ssl": true,
                                "redis_cluster_ssl_verify": false
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
