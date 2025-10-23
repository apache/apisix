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
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }


    if (!$block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
-- mock exporter http client
local client = require("opentelemetry.trace.exporter.http_client")
client.do_request = function()
    ngx.log(ngx.INFO, "opentelemetry export span")
end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->response_body) {
        $block->set_value("response_body", "passed\n");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]");
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



=== TEST 2: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 3: use default always_off sampler
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
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



=== TEST 4: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out



=== TEST 5: use trace_id_ratio sampler, default fraction = 0
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
                                "name": "trace_id_ratio"
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



=== TEST 6: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out



=== TEST 7: use trace_id_ratio sampler, fraction = 1.0
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



=== TEST 8: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 9: use parent_base sampler, default root sampler = always_off
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
                                "name": "parent_base"
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



=== TEST 10: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out



=== TEST 11: use parent_base sampler, root sampler = always_on
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
                                        "name": "always_on"
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



=== TEST 12: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 13: use parent_base sampler, root sampler = trace_id_ratio with default fraction = 0
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



=== TEST 14: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out



=== TEST 15: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 16: use parent_base sampler, root sampler = trace_id_ratio with fraction = 1
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



=== TEST 17: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 18: not trigger opentelemetry, trace_flag = 0
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-00
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out



=== TEST 19: set additional_attributes
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



=== TEST 20: trigger opentelemetry, test trace_id_source=x-request-id, custom resource, additional_attributes
--- extra_yaml_config
plugins:
    - opentelemetry
plugin_attr:
    opentelemetry:
        trace_id_source: x-request-id
        resource:
            service.name: test
            test_key: test_val
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
--- extra_init_by_lua
    local core = require("apisix.core")
    local otlp = require("opentelemetry.trace.exporter.otlp")
    local span_kind = require("opentelemetry.trace.span_kind")
    otlp.export_spans = function(self, spans)
        if (#spans ~= 1) then
            ngx.log(ngx.ERR, "unexpected spans length: ", #spans)
            return
        end

        local span = spans[1]
        if span:context().trace_id ~= "01010101010101010101010101010101" then
            ngx.log(ngx.ERR, "unexpected trace id: ", span:context().trace_id)
            return
        end

        local current_span_kind = span:plain().kind
        if current_span_kind ~= span_kind.server then
            ngx.log(ngx.ERR, "expected span.kind to be server but got ", current_span_kind)
            return
        end

        if span.name ~= "/opentracing?foo=bar&a=b" then
            ngx.log(ngx.ERR, "expect span name: /opentracing?foo=bar&a=b, but got ", span.name)
            return
        end

        local expected_resource_attrs = {
            test_key = "test_val",
        }
        expected_resource_attrs["service.name"] = "test"
        expected_resource_attrs["telemetry.sdk.language"] = "lua"
        expected_resource_attrs["telemetry.sdk.name"] = "opentelemetry-lua"
        expected_resource_attrs["telemetry.sdk.version"] = "0.1.1"
        expected_resource_attrs["hostname"] = core.utils.gethostname()
        local actual_resource_attrs = span.tracer.provider.resource:attributes()
        if #actual_resource_attrs ~= 6 then
            ngx.log(ngx.ERR, "expect len(actual_resource) = 6, but got ", #actual_resource_attrs)
            return
        end
        for _, attr in ipairs(actual_resource_attrs) do
            local expected_val = expected_resource_attrs[attr.key]
            if not expected_val then
                ngx.log(ngx.ERR, "unexpected resource attr key: ", attr.key)
                return
            end
            if attr.value.string_value ~= expected_val then
                ngx.log(ngx.ERR, "unexpected resource attr val: ", attr.value.string_value)
                return
            end
        end

        local expected_attributes = {
            service = "service_name",
            route = "route_name",
            http_user_agent = "test_nginx",
            arg_foo = "bar",
            cookie_token = "auth_token",
            remote_addr = "127.0.0.1",
        }
        if #span.attributes ~= 6 then
            ngx.log(ngx.ERR, "expect len(span.attributes) = 6, but got ", #span.attributes)
            return
        end
        for _, attr in ipairs(span.attributes) do
            local expected_val = expected_attributes[attr.key]
            if not expected_val then
                ngx.log(ngx.ERR, "unexpected attr key: ", attr.key)
                return
            end
            if attr.value.string_value ~= expected_val then
                ngx.log(ngx.ERR, "unexpected attr val: ", attr.value.string_value)
                return
            end
        end

        ngx.log(ngx.INFO, "opentelemetry export span")
    end
--- request
GET /opentracing?foo=bar&a=b
--- more_headers
X-Request-Id: 01010101010101010101010101010101
User-Agent: test_nginx
Cookie: token=auth_token;
--- response_body
opentracing
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 21: create route for /specific_status
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
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



=== TEST 22: 500 status, test span.status
--- extra_init_by_lua
    local otlp = require("opentelemetry.trace.exporter.otlp")
    otlp.export_spans = function(self, spans)
        if (#spans ~= 1) then
            ngx.log(ngx.ERR, "unexpected spans length: ", #spans)
            return
        end

        local span = spans[1]
        if span.status.code ~= 2 then
            ngx.log(ngx.ERR, "unexpected status.code: ", span.status.code)
        end
        if span.status.message ~= "upstream response status: 500" then
            ngx.log(ngx.ERR, "unexpected status.message: ", span.status.message)
        end

        ngx.log(ngx.INFO, "opentelemetry export span")
    end
--- request
GET /specific_status
--- more_headers
X-Test-Upstream-Status: 500
--- error_code: 500
--- response_body
upstream status: 500
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 23: test response empty body
--- extra_init_by_lua
    local otlp = require("opentelemetry.trace.exporter.otlp")
    otlp.export_spans = function(self, spans)
        ngx.log(ngx.INFO, "opentelemetry export span")
    end
--- request
HEAD /specific_status
--- response_body
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span
