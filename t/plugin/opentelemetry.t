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
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
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
                    "collector": {
                        "address": "127.0.0.1:4318",
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
                        }
                    },
                    "trace_id_source": "x-request-id"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 2: add plugin
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



=== TEST 3: trigger opentelemetry
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 4: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*opentelemetry-lua.*/



=== TEST 5: use trace_id_ratio sampler, fraction = 1.0
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



=== TEST 6: trigger opentelemetry
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 7: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*opentelemetry-lua.*/



=== TEST 8: use parent_base sampler, root sampler = trace_id_ratio with default fraction = 0
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



=== TEST 9: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- wait: 2
--- response_body
opentracing



=== TEST 10: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*"traceId":"00000000000000000000000000000001",.*/



=== TEST 11: use parent_base sampler, root sampler = trace_id_ratio with fraction = 1
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



=== TEST 12: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- wait: 2
--- response_body
opentracing



=== TEST 13: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*"traceId":"00000000000000000000000000000001",.*/



=== TEST 14: set additional_attributes
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



=== TEST 15: trigger opentelemetry
--- request
GET /opentracing?foo=bar&a=b
--- more_headers
X-Request-Id: 01010101010101010101010101010101
User-Agent: test_nginx
Cookie: token=auth_token;
--- wait: 2
--- response_body
opentracing



=== TEST 16: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*\/opentracing\?foo=bar.*/



=== TEST 17: create route for /specific_status
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



=== TEST 18: test response empty body
--- request
HEAD /specific_status
--- response_body
--- wait: 2



=== TEST 19: check log
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*\/specific_status.*/



=== TEST 20: set additional_attributes with numeric nginx variables
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
                            },
                            "additional_attributes": [
                                "request_time",
                                "upstream_response_time",
                                "bytes_sent"
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



=== TEST 21: trigger opentelemetry, numeric nginx variables must not cause encode error
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 22: check span exported with numeric additional attributes
# Asserts that numeric nginx variables land as `stringValue` (not intValue,
# not dropped) once additional_attributes is configured for them.
# upstream_response_time is intentionally not checked: this test serves
# /opentracing directly, so $upstream_response_time is nil and the plugin
# correctly omits the attribute. request_time and bytes_sent are always set.
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*opentelemetry-lua.*"key":"request_time","value":\{"stringValue":"[^"]+"\}.*"key":"bytes_sent","value":\{"stringValue":"[^"]+"\}.*/s



=== TEST 23: setup consumer_name in additional_attributes
--- extra_yaml_config
plugins:
    - opentelemetry
    - key-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "john",
                    "plugins": {
                        "key-auth": {
                            "key": "john-key"
                        }
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
                    "plugins": {
                        "key-auth": {},
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            },
                            "additional_attributes": [
                                "consumer_name"
                            ]
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



=== TEST 24: trigger opentelemetry with consumer
--- extra_yaml_config
plugins:
    - opentelemetry
    - key-auth
--- request
GET /opentracing
--- more_headers
X-Request-Id: 01010101010101010101010101010102
apikey: john-key
--- wait: 2
--- response_body
opentracing



=== TEST 25: check consumer_name in span attributes
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*consumer_name.*john.*/



=== TEST 26: set additional_header_prefix_attributes with header added by lower-priority plugin
--- extra_yaml_config
plugins:
    - opentelemetry
    - serverless-pre-function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx) ngx.req.set_header('x-injected-by-plugin', 'test-value') end"]
                        },
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            },
                            "additional_header_prefix_attributes": [
                                "x-injected-*"
                            ]
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



=== TEST 27: trigger opentelemetry with header injected by lower-priority plugin
--- extra_yaml_config
plugins:
    - opentelemetry
    - serverless-pre-function
--- request
GET /opentracing
--- more_headers
X-Request-Id: 01010101010101010101010101010103
--- wait: 2
--- response_body
opentracing



=== TEST 28: check header from lower-priority plugin appears in span attributes
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*x-injected-by-plugin.*test-value.*/



=== TEST 29: updating plugin_metadata rebuilds the cached tracer on a warm worker
--- extra_yaml_config
apisix:
    tracing: true
plugins:
    - opentelemetry
--- config
    location /setup_first {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local plugin = require("apisix.plugin")
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry', ngx.HTTP_PUT,
                [[{"batch_span_processor":{"max_export_batch_size":1,"inactive_timeout":0.5},"collector":{"address":"127.0.0.1:4318"},"resource":{"service.name":"otel-meta-change-first"}}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                [[{"plugins":{"opentelemetry":{"sampler":{"name":"always_on"}}},"upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"uri":"/opentracing"}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            -- wait until this worker sees the metadata so the warm-up span uses it
            local seen
            for _ = 1, 50 do
                local m = plugin.plugin_metadata("opentelemetry")
                if m and m.value and m.value.resource
                    and m.value.resource["service.name"] == "otel-meta-change-first" then
                    seen = true
                    break
                end
                ngx.sleep(0.1)
            end
            if not seen then
                ngx.status = 500
                ngx.say("metadata did not propagate")
                return
            end
            ngx.say("ok")
        }
    }
    location /setup_second {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local plugin = require("apisix.plugin")
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry', ngx.HTTP_PUT,
                [[{"batch_span_processor":{"max_export_batch_size":1,"inactive_timeout":0.5},"collector":{"address":"127.0.0.1:4318"},"resource":{"service.name":"otel-meta-change-second"}}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            -- wait until this worker sees the updated metadata before the next span
            local seen
            for _ = 1, 50 do
                local m = plugin.plugin_metadata("opentelemetry")
                if m and m.value and m.value.resource
                    and m.value.resource["service.name"] == "otel-meta-change-second" then
                    seen = true
                    break
                end
                ngx.sleep(0.1)
            end
            if not seen then
                ngx.status = 500
                ngx.say("metadata did not propagate")
                return
            end
            ngx.say("ok")
        }
    }
--- pipelined_requests eval
["GET /setup_first", "GET /opentracing", "GET /setup_second", "GET /opentracing"]
--- response_body eval
["ok\n", "opentracing\n", "ok\n", "opentracing\n"]
--- wait: 3



=== TEST 30: core span from inject_core_spans must carry the updated service.name
--- exec
grep apisix.phase.access ci/pod/otelcol-contrib/data-otlp.json | tail -n 1
--- response_body eval
qr/otel-meta-change-second/



=== TEST 31: reset metadata trace_id_source = x-request-id
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
                        "request_timeout": 3
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 32: reset route for x-request-id validation
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



=== TEST 33: invalid (UUID) x-request-id should not crash
--- request
GET /opentracing
--- more_headers
X-Request-Id: 550e8400-e29b-41d4-a716-446655440000
--- wait: 2
--- response_body
opentracing
--- no_error_log
[error]



=== TEST 34: invalid x-request-id still exports a valid random trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"[0-9a-f]{32}"/



=== TEST 35: all-zero x-request-id must not be used as trace id
--- request
GET /opentracing
--- more_headers
X-Request-Id: 00000000000000000000000000000000
--- wait: 2
--- response_body
opentracing



=== TEST 36: all-zero id is replaced by a non-zero random trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"(?!0{32})[0-9a-f]{32}"/



=== TEST 37: uppercase 32-hex x-request-id is used
--- request
GET /opentracing
--- more_headers
X-Request-Id: 550E8400E29B41D4A716446655440000
--- wait: 2
--- response_body
opentracing



=== TEST 38: uppercase 32-hex is lowercased and used as trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"550e8400e29b41d4a716446655440000"/



=== TEST 39: duplicated x-request-id header should not crash
--- request
GET /opentracing
--- more_headers
X-Request-Id: 550e8400e29b41d4a716446655440000
X-Request-Id: aabbccddeeff00112233445566778899
--- wait: 2
--- response_body
opentracing
--- no_error_log
[error]



=== TEST 40: missing x-request-id falls back to default generator
--- request
GET /opentracing
--- wait: 2
--- response_body
opentracing



=== TEST 41: missing x-request-id still exports a valid trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"[0-9a-f]{32}"/



=== TEST 42: non-hex x-request-id falls back to default generator
--- request
GET /opentracing
--- more_headers
X-Request-Id: zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
--- wait: 2
--- response_body
opentracing



=== TEST 43: non-hex x-request-id still exports a valid trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"[0-9a-f]{32}"/



=== TEST 44: empty x-request-id falls back to default generator
--- request
GET /opentracing
--- more_headers
X-Request-Id:
--- wait: 2
--- response_body
opentracing
--- no_error_log
[error]



=== TEST 45: empty x-request-id still exports a valid trace id
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"[0-9a-f]{32}"/



=== TEST 46: switch metadata trace_id_source back to random
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
                    "trace_id_source": "random",
                    "resource": {
                        "service.name": "APISIX"
                    },
                    "collector": {
                        "address": "127.0.0.1:4318",
                        "request_timeout": 3
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 47: after switching to random, send a valid 32-hex x-request-id
--- request
GET /opentracing
--- more_headers
X-Request-Id: 550e8400e29b41d4a716446655440000
--- wait: 2
--- response_body
opentracing



=== TEST 48: x-request-id must be ignored once trace_id_source is random
--- exec
tail -n 1 ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/"traceId"\s*:\s*"(?!550e8400e29b41d4a716446655440000)[0-9a-f]{32}"/
