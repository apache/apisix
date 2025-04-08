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
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - opentelemetry
    - proxy-rewrite
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }
    if (!defined $block->response_body) {
        $block->set_value("response_body", "passed\n");
    }
    $block;
});
repeat_each(1);
no_long_string();
no_root_location();
log_level("debug");

run_tests;

__DATA__

=== TEST 1: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_PUT,
                [[{
                    "batch_span_processor": {
                        "max_export_batch_size": 1,
                        "inactive_timeout": 0.5
                    },
                    "trace_id_source": "x-request-id",
                    "resource": {
                        "service.name": "APISIX"
                    },
                    "collector": {
                        "address": "127.0.0.1:4318",
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
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



=== TEST 2: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "route-name",
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        },
                        "proxy-rewrite": {"uri": "/opentracing"}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/articles/*/comments"
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



=== TEST 3: trigger opentelemetry
--- request
GET /articles/12345/comments?foo=bar
--- more_headers
User-Agent: test-client
--- wait: 2
--- response_body
opentracing



=== TEST 4: (resource) check service.name
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"service.name","value":\{"stringValue":"APISIX"\}\}/



=== TEST 5: (span) check name
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"name":"GET \/articles\/\*\/comments"/



=== TEST 6: (span) check http.status_code
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"http.status_code","value":\{"intValue":"200"\}\}/



=== TEST 7: (span) check http.method
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"http.method","value":\{"stringValue":"GET"\}\}/



=== TEST 8: (span) check http.host
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"net.host.name","value":\{"stringValue":"localhost"\}\}/



=== TEST 9: (span) check http.user_agent
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"http.user_agent","value":\{"stringValue":"test-client"\}\}/



=== TEST 10: (span) check http.target
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"http.target","value":\{"stringValue":"\/articles\/12345\/comments\?foo=bar"\}\}/



=== TEST 11: (span) check http.route
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"http.route","value":\{"stringValue":"\/articles\/\*\/comments"\}\}/



=== TEST 12: (span) check apisix.route_id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"apisix.route_id","value":\{"stringValue":"1"\}\}/



=== TEST 13: (span) check apisix.route_name
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/\{"key":"apisix.route_name","value":\{"stringValue":"route-name"\}\}/
