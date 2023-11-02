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
plugin_attr:
    opentelemetry:
        trace_id_source: x-request-id
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
        collector:
            address: 127.0.0.1:4318
            request_timeout: 3
            request_headers:
                foo: bar
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

=== TEST 1: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        }
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t



=== TEST 2: trigger opentelemetry
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 3: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*opentelemetry-lua.*/



=== TEST 4: use trace_id_ratio sampler, fraction = 1.0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "trace_id_ratio",
                                "options": {
                                    "fraction": 1.0
                                }
                            }
                        }
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t



=== TEST 5: trigger opentelemetry
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 6: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*opentelemetry-lua.*/



=== TEST 7: use parent_base sampler, root sampler = trace_id_ratio with default fraction = 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base",
                                "options": {
                                    "root": {
                                        "name": "trace_id_ratio"
                                    }
                                }
                            }
                        }
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t



=== TEST 8: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- wait: 2
--- response_body
opentracing



=== TEST 9: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*"traceId":"00000000000000000000000000000001",.*/



=== TEST 10: use parent_base sampler, root sampler = trace_id_ratio with fraction = 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base",
                                "options": {
                                    "root": {
                                        "name": "trace_id_ratio",
                                        "options": {
                                            "fraction": 1.0
                                        }
                                    }
                                }
                            }
                        }
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t



=== TEST 11: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- wait: 2
--- response_body
opentracing



=== TEST 12: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*"traceId":"00000000000000000000000000000001",.*/



=== TEST 13: set additional_attributes
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
                ngx.say(body)
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "route_name",
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            },
                            "additional_attributes": [
                                "http_user_agent",
                                "arg_foo",
                                "cookie_token",
                                "remote_addr"
                            ]
                        }
                    },
                    "uri": "/opentracing",
                    "service_id": "1"
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



=== TEST 14: trigger opentelemetry
--- request
GET /opentracing?foo=bar&a=b
--- more_headers
X-Request-Id: 01010101010101010101010101010101
User-Agent: test_nginx
Cookie: token=auth_token;
--- wait: 2
--- response_body
opentracing



=== TEST 15: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*\/opentracing\?foo=bar.*/



=== TEST 16: create route for /specific_status
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "route_name",
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        }
                    },
                    "uri": "/specific_status",
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



=== TEST 17: test response empty body
--- request
HEAD /specific_status
--- response_body
--- wait: 2



=== TEST 18: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*\/specific_status.*/
