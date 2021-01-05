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



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.prometheus")
            local ok, err = plugin.check_schema({
                invalid = "invalid"
                })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
additional properties forbidden, found invalid
--- no_error_log
[error]



=== TEST 3: set it in route
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



=== TEST 4: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body_like
apisix_etcd_reachable 1
--- no_error_log
[error]



=== TEST 5: request from client (all hit)
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 6: request from client (part hit)
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 7: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 8: test for unsupported method
--- request
PATCH /apisix/prometheus/metrics
--- error_code: 404



=== TEST 9: set it in route (with wrong property)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {
                            "invalid_property": 1
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
{"error_msg":"failed to check the configuration of plugin prometheus err: additional properties forbidden, found invalid_property"}
--- no_error_log
[error]



=== TEST 10: set it in service (with wrong property)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {
                            "invalid_property": 1
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin prometheus err: additional properties forbidden, found invalid_property"}
--- no_error_log
[error]



=== TEST 11: set route without id in post body
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



=== TEST 12: pipeline of client request
--- pipelined_requests eval
["GET /hello", "GET /not_found", "GET /hello", "GET /hello"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 13: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 14: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_count\{type="request",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 15: create service
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



=== TEST 16: use service 1 in route 1
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



=== TEST 17: pipeline of client request
--- pipelined_requests eval
["GET /hello1", "GET /not_found", "GET /hello1", "GET /hello1"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 18: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="2",service="1",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 19: delete route 2
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



=== TEST 20: set it in route with plugin `fault-injection`
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



=== TEST 21: pipeline of client request
--- pipelined_requests eval
["GET /hello", "GET /not_found", "GET /hello", "GET /hello"]
--- error_code eval
[200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 22: set it in global rule
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



=== TEST 23: request from client
--- pipelined_requests eval
["GET /hello3", "GET /hello3"]
--- error_code eval
[404, 404]
--- no_error_log
[error]



=== TEST 24: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="3",matched_uri="\/hello3",matched_host="",service="",consumer="",node="127.0.0.1"\} 2/
--- no_error_log
[error]



=== TEST 25: fetch the prometheus metric data with `overhead`
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/.*apisix_http_overhead_bucket.*/
--- no_error_log
[error]



=== TEST 26: add service 3 to distinguish other services
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



=== TEST 27: add a route 4 to redirect /sleep1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": 3,
                    "uri": "/sleep1"
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



=== TEST 28: request from client to /sleep1 ( all hit)
--- pipelined_requests eval
["GET /sleep1", "GET /sleep1", "GET /sleep1"]
--- error_code eval
[200, 200, 200]
--- no_error_log
[error]



=== TEST 29: fetch the prometheus metric data with `overhead`(the overhead < 1s)
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_overhead_bucket.*service=\"3\".*le=\"00500.0.*/
--- no_error_log
[error]



=== TEST 30: delete route 4
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



=== TEST 31: delete service 3
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



=== TEST 32: fetch the prometheus metric data with `modify_indexes consumers`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="consumers"\} \d+/
--- no_error_log
[error]



=== TEST 33: fetch the prometheus metric data with `modify_indexes global_rules`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="global_rules"\} \d+/
--- no_error_log
[error]



=== TEST 34: fetch the prometheus metric data with `modify_indexes max_modify_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="max_modify_index"\} \d+/
--- no_error_log
[error]



=== TEST 35: fetch the prometheus metric data with `modify_indexes protos`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="protos"\} \d+/
--- no_error_log
[error]



=== TEST 36: fetch the prometheus metric data with `modify_indexes routes`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="routes"\} \d+/
--- no_error_log
[error]



=== TEST 37: fetch the prometheus metric data with `modify_indexes services`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="services"\} \d+/
--- no_error_log
[error]



=== TEST 38: fetch the prometheus metric data with `modify_indexes ssls`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="ssls"\} \d+/
--- no_error_log
[error]



=== TEST 39: fetch the prometheus metric data with `modify_indexes stream_routes`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="stream_routes"\} \d+/
--- no_error_log
[error]



=== TEST 40: fetch the prometheus metric data with `modify_indexes upstreams`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="upstreams"\} \d+/
--- no_error_log
[error]



=== TEST 41: fetch the prometheus metric data with `modify_indexes prev_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="prev_index"\} \d+/
--- no_error_log
[error]



=== TEST 42: fetch the prometheus metric data with `modify_indexes x_etcd_index`
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_etcd_modify_indexes\{key="x_etcd_index"\} \d+/
--- no_error_log
[error]



=== TEST 43: fetch the prometheus metric data -- hostname
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_node_info\{hostname=".*"\} 1/
--- no_error_log
[error]



=== TEST 44: don't try to provide etcd metrics when you don't use it
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



=== TEST 45: set route with key-auth enabled for consumer metrics
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {},
                        "key-auth": {}
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



=== TEST 46: pipeline of client request without api-key
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[401, 401, 401, 401]
--- no_error_log
[error]



=== TEST 47: fetch the prometheus metric data: consumer is empty
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 48: set consumer for metics data collection
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "key-auth": {
                                    "key": "auth-one"
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 49: pipeline of client request with successfully authorized
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 50: fetch the prometheus metric data: consumer is jack
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="200",route="1",matched_uri="\/hello",matched_host="",service="",consumer="jack",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 51: set route(id: 9)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "hosts": ["foo.com", "bar.com"],
                        "uris": ["/foo*", "/bar*"]
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



=== TEST 52: 404 Route Not Found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 53: fetch the prometheus metric data: 404 Route Not Found
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="",matched_uri="",matched_host="",service="localhost",consumer="",node=""\} \d+/
--- no_error_log
[error]



=== TEST 54: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /foo1
--- more_headers
Host: foo.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 55: fetch the prometheus metric data: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/foo\*",matched_host="foo.com",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 56: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /bar1
--- more_headers
Host: bar.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 57: fetch the prometheus metric data: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/bar\*",matched_host="bar.com",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 58: customize export uri, not found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /apisix/prometheus/metrics
--- error_code: 404
--- no_error_log
[error]



=== TEST 59: customize export uri, found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /a
--- error_code: 200
--- no_error_log
[error]



=== TEST 60: customize export uri, missing plugin, use default
--- yaml_config
plugin_attr:
    x:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- no_error_log
[error]



=== TEST 61: customize export uri, missing attr, use default
--- yaml_config
plugin_attr:
    prometheus:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- no_error_log
[error]



=== TEST 62: set sys plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "syslog": {
			                    "host": "127.0.0.1",
			                    "include_req_body": false,
			                    "max_retry_times": 1,
			                    "tls": false,
			                    "retry_interval": 1,
			                    "batch_max_size": 1000,
			                    "buffer_duration": 60,
			                    "port": 1000,
			                    "name": "sys-logger",
			                    "flush_limit": 4096,
			                    "sock_type": "tcp",
			                    "timeout": 3,
			                    "drop_limit": 1048576,
			                    "pool_size": 5
		                    }                        
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics"
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



=== TEST 63: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 64: check sys logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sys-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 65: set zipkin plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9447",
                                "service_name": "APISIX",
                                "sample_ratio": 1
                            }                     
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics"
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



=== TEST 66: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 67: check zipkin log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="zipkin_report",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 68: set http plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/9',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "http-logger": {
                                "inactive_timeout": 5,
                                "include_req_body": false,
                                "timeout": 3,
                                "name": "http-logger",
                                "retry_delay": 1,
                                "buffer_duration": 60,
                                "uri": "http://127.0.0.1:19080/report",
                                "concat_method": "json",
                                "batch_max_size": 1000,
                                "max_retry_count": 0
                            }                     
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics"
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



=== TEST 69: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 70: check http log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="http-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 71: set tcp-logger plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/10',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "include_req_body": false,
                                "timeout": 1000,
                                "name": "tcp-logger",
                                "retry_delay": 1,
                                "buffer_duration": 60,
                                "port": 1000,
                                "batch_max_size": 1000,
                                "inactive_timeout": 5,
                                "tls": false,
                                "max_retry_count": 0
                            }                    
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics-10"
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



=== TEST 72:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 73: check tcp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="tcp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 74: set udp-logger plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/10',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "udp-logger": {
                                "host": "127.0.0.1",
                                "port": 1000,
                                "include_req_body": false,
                                "timeout": 3,
                                "batch_max_size": 1000,
                                "name": "udp-logger",
                                "inactive_timeout": 5,
                                "buffer_duration": 60
                            }                     
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics-10"
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



=== TEST 75:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 76: check udp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="udp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 77: set sls-logger plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/10',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "prometheus": {},
                            "sls-logger": {
                                "host": "127.0.0.1",
                                "batch_max_size": 1000,
                                "name": "sls-logger",
                                "inactive_timeout": 5,
                                "logstore": "your_logstore",
                                "buffer_duration": 60,
                                "port": 10009,
                                "max_retry_count": 0,
                                "retry_delay": 1,
                                "access_key_id": "your_access_id",
                                "access_key_secret": "your_key_secret",
                                "timeout": 5000,
                                "project": "your_project"
                            }                      
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/batch-process-metrics-10"
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



=== TEST 78:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 79: check sls-logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sls-logger",route_id="10",server_addr="127.0.0.1"\} \d+/
