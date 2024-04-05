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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: pre-create public API route
--- config
    location /t {
        content_by_lua_block {

            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/prometheus/metrics"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
        }
    }



=== TEST 2: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/10',
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
--- response_body
passed



=== TEST 3: client request
--- yaml_config
plugin_attr:
    prometheus:
        metrics:
            bandwidth:
                extra_labels:
                    - upstream_addr: $upstream_addr
                    - upstream_status: $upstream_status
--- request
GET /hello



=== TEST 4: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="10",service="",consumer="",node="127.0.0.1",upstream_addr="127.0.0.1:1980",upstream_status="200"\} \d+/



=== TEST 5: client request, label with nonexist ngx variable
--- yaml_config
plugin_attr:
    prometheus:
        metrics:
            http_status:
                extra_labels:
                    - dummy: $dummy
--- request
GET /hello



=== TEST 6: fetch the prometheus metric data, with nonexist ngx variable
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="200",route="10",matched_uri="\/hello",matched_host="",service="",consumer="",node="127.0.0.1",dummy=""\} \d+/



=== TEST 7: set route
--- yaml_config
plugin_attr:
    prometheus:
        default_buckets:
            - 15
            - 55
            - 105
            - 205
            - 505
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
                    "uri": "/hello1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /t", "GET /hello1"]
--- response_body eval
["passed\n", "hello1 world\n"]



=== TEST 8: fetch metrics
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="15"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="55"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="105"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="205"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="505"\} \d+/



=== TEST 9: set route with prometheus ttl
--- yaml_config
plugin_attr:
    prometheus:
        default_buckets:
            - 15
            - 55
            - 105
            - 205
            - 505
        expire: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/prometheus/metrics"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

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
                    "uri": "/hello1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/hello1',
                ngx.HTTP_GET,
                "",
                nil,
                nil
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(2)

            local code, pass, body = t('/apisix/prometheus/metrics',
                ngx.HTTP_GET,
                "",
                nil,
                nil
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_unlike eval
qr/apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="15"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="55"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="105"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="205"\} \d+
apisix_http_latency_bucket\{type="upstream",route="1",service="",consumer="",node="127.0.0.1",le="505"\} \d+/



=== TEST 10: set sys plugins
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



=== TEST 11: remove prometheus -> reload -> send batch request -> add prometheus for next tests
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            local t = require("lib.test_admin").test
                    ngx.sleep(0.1)
            local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
    - example-plugin
plugin_attr:
    example-plugin:
        val: 1
        ]]
            require("lib.test_admin").set_config_yaml(data)
            local code, _, org_body = t('/v1/plugins/reload', ngx.HTTP_PUT)
            local code, body = t('/batch-process-metrics',
                 ngx.HTTP_GET
                )
            
            ngx.status = code
            ngx.say(body)


            local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
    - prometheus
plugin_attr:
    example-plugin:
        val: 1
        ]]
            require("lib.test_admin").set_config_yaml(data)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/



=== TEST 12: fetch prometheus metrics -> batch_process_entries metrics should not be present
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_unlike eval
qr/apisix_batch_process_entries\{name="sys-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 13: hit batch-process-metrics with prometheus enabled from TEST 11
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 14: batch_process_entries metrics should be present now
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sys-logger",route_id="9",server_addr="127.0.0.1"\} \d+/
