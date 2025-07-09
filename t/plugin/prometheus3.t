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
});

run_tests;

__DATA__

=== TEST 1: setup public API route and test route
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/plugin_configs/1",
                    data = [[{
                        "plugins": {
                            "prometheus":{}
                        }
                    }]]
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugin_config_id": 1,
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/prometheus/metrics"
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
"201passed\n" x 3



=== TEST 2: hit
--- pipelined_requests eval
["GET /hello", "GET /apisix/prometheus/metrics"]
--- error_code eval
[200, 200]



=== TEST 3: apisix_batch_process_entries, mess with global rules
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
                        "uri": "/batch-process-metrics-aa"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "host": "127.0.0.1",
                        "port": 1999
                    },
                    "max_retry_count": 1000,
                    "level": "NOTICE"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1979"
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



=== TEST 4: check metrics
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 1
plugins:
  - public-api
  - error-log-logger
  - prometheus
  - http-logger
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/batch-process-metrics-aa"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.sleep(2)
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/apisix/prometheus/metrics"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.body)
        }
    }
--- response_body_like eval
qr/apisix_batch_process_entries\{name="http logger",route_id="1",server_addr="127.0.0.1"\} \d+/



=== TEST 5: set prometheus plugin at both global rule and route
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
                    "uri": "/opentracing"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
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
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: test prometheus plugin at both global rule and route
--- request
GET /opentracing
--- response_body
opentracing



=== TEST 7: fetch prometheus plugin at both global rule and route data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="200",route="1",matched_uri="\/opentracing",matched_host="",service="",consumer="",node="127.0.0.1\"} 1/
