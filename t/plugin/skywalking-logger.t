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
use t::APISIX 'no_plan';

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 1986;
        server_tokens off;

        location /v3/logs {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.WARN, "skywalking-logger body: ", data)
                core.log.warn(core.json.encode(core.request.get_body(), true))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking-logger")
            local ok, err = plugin.check_schema({endpoint_addr = "http://127.0.0.1"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }



=== TEST 2: full schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking-logger")
            local ok, err = plugin.check_schema({endpoint_addr = "http://127.0.0.1",
                                                 timeout = 3,
                                                 name = "skywalking-logger",
                                                 max_retry_count = 2,
                                                 retry_delay = 2,
                                                 buffer_duration = 2,
                                                 inactive_timeout = 2,
                                                 batch_max_size = 500,
                                                 })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }



=== TEST 3: uri is missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking-logger")
            local ok, err = plugin.check_schema({timeout = 3,
                                                 name = "skywalking-logger",
                                                 max_retry_count = 2,
                                                 retry_delay = 2,
                                                 buffer_duration = 2,
                                                 inactive_timeout = 2,
                                                 batch_max_size = 500,
                                                 })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "endpoint_addr" is required
done



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "skywalking-logger": {
                                "endpoint_addr": "http://127.0.0.1:1986",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "service_instance_name": "$hostname"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
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



=== TEST 5: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[skywalking logger] successfully processed the entries
--- wait: 0.5



=== TEST 6: test trace context header
--- request
GET /opentracing
--- more_headers
sw8: 1-YWU3MDk3NjktNmUyMC00YzY4LTk3MzMtMTBmNDU1MjE2Y2M1-YWU3MDk3NjktNmUyMC00YzY4LTk3MzMtMTBmNDU1MjE2Y2M1-1-QVBJU0lY-QVBJU0lYIEluc3RhbmNlIE5hbWU=-L2dldA==-dXBzdHJlYW0gc2VydmljZQ==
--- response_body
opentracing
--- error_log eval
qr/.*\\\"traceContext\\\":\{(\\\"traceSegmentId\\\":\\\"ae709769-6e20-4c68-9733-10f455216cc5\\\"|\\\"traceId\\\":\\\"ae709769-6e20-4c68-9733-10f455216cc5\\\"|\\\"spanId\\\":1|,){5}\}.*/
--- wait: 0.5



=== TEST 7: test wrong trace context header
--- request
GET /opentracing
--- more_headers
sw8: 1-YWU3MDk3NjktNmUyMC00YzY4LTk3MzMtMTBmNDU1MjE2Y2M1-YWU3MDk3NjktNmUyMC00YzY4LTk3MzMtMTBmNDU1MjE2Y2M1-1-QVBJU0lY-QVBJU0lYIEluc3RhbmNlIE5hbWU=-L2dldA==
--- response_body
opentracing
--- error_log eval
qr/failed to parse trace_context header:/
--- wait: 0.5



=== TEST 8: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/skywalking-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "@timestamp": "$time_iso8601",
                        "client_ip": "$remote_addr"
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



=== TEST 9: access local server and test log format
--- request
GET /opentracing
--- response_body
opentracing
--- error_log eval
qr/.*\{\\\"json\\\":\\\"\{(\\\\\\\"\@timestamp\\\\\\\":\\\\\\\".*\\\\\\\"|\\\\\\\"client_ip\\\\\\\":\\\\\\\"127\.0\.0\.1\\\\\\\"|\\\\\\\"host\\\\\\\":\\\\\\\"localhost\\\\\\\"|\\\\\\\"route_id\\\\\\\":\\\\\\\"1\\\\\\\"|,){7}\}/
--- wait: 0.5



=== TEST 10: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "skywalking-logger": {
                                "endpoint_addr": "http://127.0.0.1:1986",
                                "log_format": {
                                    "my_ip": "$remote_addr"
                                },
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
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



=== TEST 11: access local server and test log format
--- request
GET /opentracing
--- response_body
opentracing
--- error_log eval
qr/.*\{\\\"json\\\":.*\\\\\\"my_ip\\\\\\":\\\\\\"127\.0\.0\.1\\\\\\".*\}/
--- wait: 0.5



=== TEST 12: test serviceInstance $hostname
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log eval
qr/\\\"serviceInstance\\\":\\\"\$hostname\\\"/
qr/\\\"serviceInstance\\\":\\\"\\\"/
--- wait: 0.5



=== TEST 13: add plugin with 'include_req_body' setting, collect request log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/skywalking-logger', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "skywalking-logger": {
                                "endpoint_addr": "http://127.0.0.1:1986",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "include_req_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            local code, _, body = t("/opentracing", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- error_log
\"body\":\"{\\\"sample_payload\\\":\\\"hello\\\"}\"



=== TEST 14: add plugin with 'include_resp_body' setting, collect response log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/skywalking-logger', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "skywalking-logger": {
                                "endpoint_addr": "http://127.0.0.1:1986",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "include_req_body": true,
                                "include_resp_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            local code, _, body = t("/opentracing", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- error_log
\"body\":\"opentracing\\n\"
