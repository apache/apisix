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

=== TEST 1: set route with key-auth enabled for consumer metrics
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



=== TEST 2: pipeline of client request without api-key
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[401, 401, 401, 401]
--- no_error_log
[error]



=== TEST 3: fetch the prometheus metric data: consumer is empty
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node=""\} \d+/
--- no_error_log
[error]



=== TEST 4: set consumer for metics data collection
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



=== TEST 5: pipeline of client request with successfully authorized
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 6: fetch the prometheus metric data: consumer is jack
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="200",route="1",matched_uri="\/hello",matched_host="",service="",consumer="jack",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 7: set route(id: 9)
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



=== TEST 8: set it in global rule
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
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: 404 Route Not Found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 10: fetch the prometheus metric data: 404 Route Not Found
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="",matched_uri="",matched_host="",service="localhost",consumer="",node=""\} \d+/
--- no_error_log
[error]



=== TEST 11: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /foo1
--- more_headers
Host: foo.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 12: fetch the prometheus metric data: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/foo\*",matched_host="foo.com",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 13: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /bar1
--- more_headers
Host: bar.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 14: fetch the prometheus metric data: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/bar\*",matched_host="bar.com",service="",consumer="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]



=== TEST 15: customize export uri, not found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /apisix/prometheus/metrics
--- error_code: 404
--- no_error_log
[error]



=== TEST 16: customize export uri, found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /a
--- error_code: 200
--- no_error_log
[error]



=== TEST 17: customize export uri, missing plugin, use default
--- yaml_config
plugin_attr:
    x:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- no_error_log
[error]



=== TEST 18: customize export uri, missing attr, use default
--- yaml_config
plugin_attr:
    prometheus:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- no_error_log
[error]



=== TEST 19: set sys plugins
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



=== TEST 20: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 21: check sys logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sys-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 22: set zipkin plugins
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



=== TEST 23: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 24: check zipkin log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="zipkin_report",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 25: set http plugins
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



=== TEST 26: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 27: check http log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="http-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 28: set tcp-logger plugins
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



=== TEST 29:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 30: check tcp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="tcp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 31: set udp-logger plugins
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



=== TEST 32:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 33: check udp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="udp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 34: set sls-logger plugins
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



=== TEST 35:  tigger metircs batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 36: check sls-logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sls-logger",route_id="10",server_addr="127.0.0.1"\} \d+/
