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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.prometheus")
            local ok, err = plugin.check_schema({})
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



=== TEST 2: set it in route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {}
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
--- no_error_log
[error]



=== TEST 3: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body_like
apisix_etcd_reachable 1
--- no_error_log
[error]



=== TEST 4: request from client (all hit)
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 5: request from client (part hit)
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 6: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 7: test for unsupported method
--- request
PATCH /apisix/prometheus/metrics
--- error_code: 404



=== TEST 8: set route without id in post body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {
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
--- no_error_log
[error]



=== TEST 9: pipeline of client request
--- pipelined_requests eval
["GET /hello", "GET /not_found", "GET /hello", "GET /hello"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 10: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 11: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_count\{type="request",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 12: create service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {}
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



=== TEST 13: use service 1 in route 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "service_id": 1,
                    "uri": "/hello1"
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



=== TEST 14: pipeline of client request
--- pipelined_requests eval
["GET /hello1", "GET /not_found", "GET /hello1", "GET /hello1"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 15: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="2",service="1",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 16: delete route 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
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
--- no_error_log
[error]



=== TEST 17: set it in route with plugin `fault-injection`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {},
                        "fault-injection": {
                            "abort": {
                               "http_status": 200,
                               "body": "Fault Injection!"
                            }
                        }
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
--- no_error_log
[error]



=== TEST 18: pipeline of client request
--- pipelined_requests eval
["GET /hello", "GET /not_found", "GET /hello", "GET /hello"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 19: set it in global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {}
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello3"
                }]]
            )
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
passed
--- no_error_log
[error]



=== TEST 20: request from client
--- pipelined_requests eval
["GET /hello3", "GET /hello3"]
--- error_code eval
[404, 404]
--- no_error_log
[error]



=== TEST 21: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="3",matched_uri="\/hello3",matched_host="",service="",consumer="",node="127.0.0.1"\} 2/
--- no_error_log
[error]



=== TEST 22: fetch the prometheus metric data with apisix latency
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/.*apisix_http_latency_bucket\{type="apisix".*/
--- no_error_log
[error]



=== TEST 23: add service 3 to distinguish other services
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
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



=== TEST 24: add a route 4 to redirect /mysleep?seconds=1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": 3,
                    "uri": "/mysleep"
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



=== TEST 25: request from client to /mysleep?seconds=1 ( all hit)
--- pipelined_requests eval
["GET /mysleep?seconds=1", "GET /mysleep?seconds=1", "GET /mysleep?seconds=1"]
--- error_code eval
[200, 200, 200]
--- no_error_log
[error]



=== TEST 26: fetch the prometheus metric data with apisix latency (latency < 1s)
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_bucket\{type="apisix".*service=\"3\".*le=\"500.*/
--- no_error_log
[error]



=== TEST 27: delete route 4
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
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
--- no_error_log
[error]



=== TEST 28: delete service 3
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/3',
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
--- no_error_log
[error]



=== TEST 29: fetch the prometheus metric data with `modify_indexes consumers`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="consumers"\} \d+/
--- no_error_log
[error]



=== TEST 30: fetch the prometheus metric data with `modify_indexes global_rules`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="global_rules"\} \d+/
--- no_error_log
[error]



=== TEST 31: fetch the prometheus metric data with `modify_indexes max_modify_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="max_modify_index"\} \d+/
--- no_error_log
[error]



=== TEST 32: fetch the prometheus metric data with `modify_indexes protos`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="protos"\} \d+/
--- no_error_log
[error]



=== TEST 33: fetch the prometheus metric data with `modify_indexes routes`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="routes"\} \d+/
--- no_error_log
[error]



=== TEST 34: fetch the prometheus metric data with `modify_indexes services`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="services"\} \d+/
--- no_error_log
[error]



=== TEST 35: fetch the prometheus metric data with `modify_indexes ssls`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="ssls"\} \d+/
--- no_error_log
[error]



=== TEST 36: fetch the prometheus metric data with `modify_indexes stream_routes`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="stream_routes"\} \d+/
--- no_error_log
[error]



=== TEST 37: fetch the prometheus metric data with `modify_indexes upstreams`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="upstreams"\} \d+/
--- no_error_log
[error]



=== TEST 38: fetch the prometheus metric data with `modify_indexes prev_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="prev_index"\} \d+/
--- no_error_log
[error]



=== TEST 39: fetch the prometheus metric data with `modify_indexes x_etcd_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="x_etcd_index"\} \d+/
--- no_error_log
[error]



=== TEST 40: fetch the prometheus metric data -- hostname
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_node_info\{hostname=".*"\} 1/
--- no_error_log
[error]



=== TEST 41: don't try to provide etcd metrics when you don't use it
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_/
--- response_body_unlike eval
qr/etcd/
--- no_error_log
[error]
