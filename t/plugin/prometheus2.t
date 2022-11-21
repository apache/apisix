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
            local data = {
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/metrics-custom-uri",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/a"
                    }]]
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 2



=== TEST 2: set route with key-auth enabled for consumer metrics
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
--- response_body
passed



=== TEST 3: pipeline of client request without api-key
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[401, 401, 401, 401]



=== TEST 4: fetch the prometheus metric data: consumer is empty
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",consumer="",node=""\} \d+/



=== TEST 5: set consumer for metrics data collection
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



=== TEST 6: pipeline of client request with successfully authorized
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- error_code eval
[200, 200, 200, 200]



=== TEST 7: fetch the prometheus metric data: consumer is jack
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="200",route="1",matched_uri="\/hello",matched_host="",service="",consumer="jack",node="127.0.0.1"\} \d+/



=== TEST 8: set route(id: 9)
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
--- response_body
passed



=== TEST 9: set it in global rule
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
--- response_body
passed



=== TEST 10: 404 Route Not Found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 11: fetch the prometheus metric data: 404 Route Not Found
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="",matched_uri="",matched_host="",service="",consumer="",node=""\} \d+/



=== TEST 12: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /foo1
--- more_headers
Host: foo.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 13: fetch the prometheus metric data: hit routes(uri = "/foo*", host = "foo.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/foo\*",matched_host="foo.com",service="",consumer="",node="127.0.0.1"\} \d+/



=== TEST 14: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /bar1
--- more_headers
Host: bar.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 15: fetch the prometheus metric data: hit routes(uri = "/bar*", host = "bar.com")
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="404",route="9",matched_uri="\/bar\*",matched_host="bar.com",service="",consumer="",node="127.0.0.1"\} \d+/



=== TEST 16: customize export uri, not found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /apisix/prometheus/metrics
--- error_code: 404



=== TEST 17: customize export uri, found
--- yaml_config
plugin_attr:
    prometheus:
        export_uri: /a
--- request
GET /a
--- error_code: 200



=== TEST 18: customize export uri, missing plugin, use default
--- yaml_config
plugin_attr:
    x:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200



=== TEST 19: customize export uri, missing attr, use default
--- yaml_config
plugin_attr:
    prometheus:
        y: z
--- request
GET /apisix/prometheus/metrics
--- error_code: 200



=== TEST 20: set sys plugins
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
                                "max_retry_count": 1,
                                "tls": false,
                                "retry_delay": 1,
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
--- response_body
passed



=== TEST 21: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 22: check sys logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sys-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 23: set zipkin plugins
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
--- response_body
passed



=== TEST 24: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 25: check zipkin log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="zipkin_report",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 26: set http plugins
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
--- response_body
passed



=== TEST 27: hit batch-process-metrics
--- request
GET /batch-process-metrics
--- error_code: 404



=== TEST 28: check http log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="http-logger",route_id="9",server_addr="127.0.0.1"\} \d+/



=== TEST 29: set tcp-logger plugins
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
                                "inactive_timeout": 60,
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
--- response_body
passed



=== TEST 30:  trigger metrics batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 31: check tcp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="tcp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 32: set udp-logger plugins
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
--- response_body
passed



=== TEST 33:  trigger metrics batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 34: check udp log metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="udp-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 35: set sls-logger plugins
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
--- response_body
passed



=== TEST 36:  trigger metrics batch-process-metrics
--- request
GET /batch-process-metrics-10
--- error_code: 404



=== TEST 37: check sls-logger metrics
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
--- response_body_like eval
qr/apisix_batch_process_entries\{name="sls-logger",route_id="10",server_addr="127.0.0.1"\} \d+/



=== TEST 38: create service and route both with name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "service_name",
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

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "route_name",
                    "service_id": 1,
                    "plugins": {
                        "prometheus": {
                            "prefer_name": true
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
--- response_body
passed
passed



=== TEST 39: pipeline of client request
--- request
GET /hello
--- error_code: 200



=== TEST 40: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="route_name",service="service_name",consumer="",node="127.0.0.1"\} \d+/



=== TEST 41: set route name but remove service name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
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



=== TEST 42: pipeline of client request
--- request
GET /hello
--- error_code: 200



=== TEST 43: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="route_name",service="1",consumer="",node="127.0.0.1"\} \d+/



=== TEST 44: set service name but remove route name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "service_name",
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

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "service_id": 1,
                    "plugins": {
                        "prometheus": {
                            "prefer_name": true
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
--- response_body
passed
passed



=== TEST 45: pipeline of client request
--- request
GET /hello
--- error_code: 200



=== TEST 46: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="service_name",consumer="",node="127.0.0.1"\} \d+/



=== TEST 47: remove both name, but still set prefer_name to true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "service_id": 1,
                    "plugins": {
                        "prometheus": {
                            "prefer_name": true
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
--- response_body
passed



=== TEST 48: pipeline of client request
--- request
GET /hello
--- error_code: 200



=== TEST 49: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="service_name",consumer="",node="127.0.0.1"\} \d+/



=== TEST 50: fetch the prometheus shared dict data
--- http_config
lua_shared_dict test-shared-dict 10m;
--- request
GET /apisix/prometheus/metrics
--- response_body_like
.*apisix_shared_dict_capacity_bytes\{name="test-shared-dict"\} 10485760(?:.|\n)*
apisix_shared_dict_free_space_bytes\{name="test-shared-dict"\} \d+.*
