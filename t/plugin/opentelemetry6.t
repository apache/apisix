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
    sub set_env_from_file {
        my ($env_name, $file_path) = @_;

        open my $fh, '<', $file_path or die $!;
        my $content = do { local $/; <$fh> };
        close $fh;

        $ENV{$env_name} = $content;
    }
    # set env
    set_env_from_file('TEST_CERT', 't/certs/apisix.crt');
    set_env_from_file('TEST_KEY', 't/certs/apisix.key');
    set_env_from_file('TEST2_CERT', 't/certs/test2.crt');
    set_env_from_file('TEST2_KEY', 't/certs/test2.key');
}
use t::APISIX 'no_plan';
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
apisix:
    tracing: true
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

=== TEST 1: empty file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 2: add plugin metadata
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



=== TEST 3: set route
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
                            "test1.com:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/otel_traceparent"
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



=== TEST 4: set ssl with two certs and keys in env
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                snis = {"test.com"},
                key =  "$env://TEST_KEY",
                cert = "$env://TEST_CERT",
                keys = {"$env://TEST2_KEY"},
                certs = {"$env://TEST2_CERT"}
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "snis": ["test.com"],
                        "key": "$env://TEST_KEY",
                        "cert": "$env://TEST_CERT",
                        "keys": ["$env://TEST2_KEY"],
                        "certs": ["$env://TEST2_CERT"]
                    },
                    "key": "/apisix/ssls/1"
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



=== TEST 5: trigger SSL match with SNI
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test1.com" then
            return {address = "127.0.0.2"}
        end

        error("unknown domain: " .. domain)
    end
--- exec
curl -k -D /tmp/apisix-otel-upstream-headers.txt \
    --resolve "test.com:1994:127.0.0.1" https://test.com:1994/otel_traceparent
--- wait: 5
--- response_body
opentracing



=== TEST 6: verify span tree structure
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local ok, err = otel.verify_tree(
                "ci/pod/otelcol-contrib/data-otlp.json",
                {
                    name = "GET /otel_traceparent",
                    kind = 2,
                    attributes = {
                        ["apisix.route_id"] = "1",
                        ["http.method"] = "GET",
                        ["http.status_code"] = "200",
                    },
                    children = {
                        {
                            name = "apisix.phase.access",
                            kind = 2,
                            children = {
                                { name = "sni_radixtree_match", kind = 1 },
                                { name = "http_router_match", kind = 1 },
                            }
                        },
                        { name = "resolve_dns", kind = 1 },
                        {
                            name = "apisix.upstream",
                            kind = 3,
                            within_parent = true,
                            propagated_header_file =
                                "/tmp/apisix-otel-upstream-headers.txt",
                            attributes = {
                                ["server.address"] = "127.0.0.2",
                                ["server.port"] = "1980",
                                ["http.response.status_code"] = "200",
                            },
                        },
                        { name = "apisix.phase.header_filter", kind = 2 },
                        { name = "apisix.phase.body_filter", kind = 2 },
                        { name = "apisix.phase.log.plugins.opentelemetry", kind = 1 },
                    }
                }
            )

            if not ok then
                ngx.say("FAIL:\n" .. err)
            else
                ngx.say("passed")
            end
        }
    }



=== TEST 7: clear file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 8: trigger two HTTP/2 requests on the same TLS connection
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)
        if domain == "test1.com" then
            return {address = "127.0.0.2"}
        end
        error("unknown domain: " .. domain)
    end
--- exec
curl -sk --http2 --resolve "test.com:1994:127.0.0.1" \
    https://test.com:1994/otel_traceparent https://test.com:1994/otel_traceparent
--- wait: 5
--- response_body
opentracing
opentracing



=== TEST 9: verify each HTTP/2 stream has its own isolated span set
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local ok, err = otel.verify_isolated_traces(
                "ci/pod/otelcol-contrib/data-otlp.json",
                "GET /otel_traceparent",
                2,
                {
                    "GET /otel_traceparent",
                    "apisix.phase.access",
                    "sni_radixtree_match",
                    "http_router_match",
                    "resolve_dns",
                    "apisix.upstream",
                    "apisix.phase.header_filter",
                    "apisix.phase.header_filter.plugins.opentelemetry",
                    "apisix.phase.body_filter",
                    "apisix.phase.log.plugins.opentelemetry",
                }
            )

            if not ok then
                ngx.say("FAIL:\n" .. err)
            else
                ngx.say("passed")
            end
        }
    }



=== TEST 10: clear file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 11: set route with a refused node tried before a healthy one
--- extra_yaml_config
apisix:
    tracing: true
plugins:
    - opentelemetry
    - serverless-post-function
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
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(_,c)ngx.log(5,c.var.upstream_status)end"]
                        }
                    },
                    "upstream": {
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1979, "weight": 1, "priority": 1},
                            {"host": "127.0.0.1", "port": 1980, "weight": 1, "priority": 0}
                        ],
                        "retries": 1,
                        "type": "roundrobin"
                    },
                    "uri": "/otel_traceparent"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 12: trigger a request that is retried on the second node
--- extra_yaml_config
apisix:
    tracing: true
plugins:
    - opentelemetry
    - serverless-post-function
--- exec
curl -s -D /tmp/apisix-otel-retry-headers.txt http://127.0.0.1:1984/otel_traceparent
--- wait: 5
--- response_body
opentracing
--- error_log
502, 200



=== TEST 13: verify one client span per upstream attempt
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local spans, err = otel.find_spans("ci/pod/otelcol-contrib/data-otlp.json",
                                               "apisix.upstream")
            if not spans then
                ngx.say("FAIL: ", err)
                return
            end
            if #spans ~= 2 then
                ngx.say("FAIL: expected 2 upstream spans, got ", #spans)
                return
            end

            local first, second
            local a1, a2
            for _, span in ipairs(spans) do
                local attrs = otel.get_attr_map(span)
                if tostring(attrs["server.port"]) == "1979" then
                    first, a1 = span, attrs

                elseif tostring(attrs["server.port"]) == "1980" then
                    second, a2 = span, attrs
                end
            end
            local errors = {}
            local function check(cond, msg)
                if not cond then
                    table.insert(errors, msg)
                end
            end

            check(first and second, "failed to find both upstream attempts")
            if not first or not second then
                ngx.say("FAIL:\n", table.concat(errors, "\n"))
                return
            end
            check(first.parentSpanId == second.parentSpanId,
                  "attempts should share the server span as parent")
            check(tostring(a1["server.port"]) == "1979",
                  "first attempt port: " .. tostring(a1["server.port"]))
            check(a1["http.response.status_code"] == nil,
                  "connection failure should not have HTTP status: "
                  .. tostring(a1["http.response.status_code"]))
            check(tostring(a2["server.port"]) == "1980",
                  "second attempt port: " .. tostring(a2["server.port"]))
            check(first.status and first.status.code == 2,
                  "first attempt should be marked as error")
            check(not (second.status and second.status.code == 2),
                  "second attempt should not be marked as error")
            check(tostring(a2["http.response.status_code"]) == "200",
                  "second attempt status: " .. tostring(a2["http.response.status_code"]))
            check(tonumber(first.endTimeUnixNano) <= tonumber(second.startTimeUnixNano),
                  "first attempt should end before the retry starts")

            local ok, perr = otel.check_propagated_parent(
                "/tmp/apisix-otel-retry-headers.txt", second)
            check(ok, perr)

            if #errors > 0 then
                ngx.say("FAIL:\n", table.concat(errors, "\n"))
            else
                ngx.say("passed")
            end
        }
    }



=== TEST 14: clear file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 15: set route that conditionally dispatches before exiting
--- extra_yaml_config
apisix:
    tracing: true
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
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        },
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions": [
                                "return function(_,c)c._apisix_upstream_started=c.var.arg_d end",
                                "return function() return 403 end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/short-circuit"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 16: trigger stopped requests with and without an upstream dispatch
--- extra_yaml_config
apisix:
    tracing: true
plugins:
    - opentelemetry
    - serverless-pre-function
--- exec
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1984/short-circuit
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1984/short-circuit?d=1
--- wait: 5
--- response_body
403
403



=== TEST 17: verify only the dispatched client span is exported
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local spans, err = otel.find_spans("ci/pod/otelcol-contrib/data-otlp.json",
                                               "apisix.upstream")
            if not spans then
                ngx.say("FAIL: ", err)
            elseif #spans ~= 1 then
                ngx.say("FAIL: expected one upstream span, got ", #spans)
            else
                ngx.say("passed")
            end
        }
    }



=== TEST 18: clear file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 19: set route with work before the upstream call
--- extra_yaml_config
apisix:
    tracing: true
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
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        },
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions": ["return function() ngx.sleep(0.2) end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/otel_traceparent"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 20: trigger the delayed before_proxy route
--- extra_yaml_config
apisix:
    tracing: true
plugins:
    - opentelemetry
    - serverless-pre-function
--- request
GET /otel_traceparent
--- wait: 5
--- response_body
opentracing



=== TEST 21: verify client span timing excludes earlier plugin work
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local clients, err = otel.find_spans(
                "ci/pod/otelcol-contrib/data-otlp.json", "apisix.upstream")
            if not clients then
                ngx.say("FAIL: ", err)
                return
            end
            local roots, root_err = otel.find_spans(
                "ci/pod/otelcol-contrib/data-otlp.json", "GET /otel_traceparent")
            if not roots then
                ngx.say("FAIL: ", root_err)
                return
            end
            if #clients ~= 1 or #roots ~= 1 then
                ngx.say("FAIL: expected one client/root span, got ",
                        #clients, "/", #roots)
                return
            end

            local delay = tonumber(clients[1].startTimeUnixNano)
                          - tonumber(roots[1].startTimeUnixNano)
            if delay < 150000000 then
                ngx.say("FAIL: client span started before delayed plugin completed: ", delay)
            else
                ngx.say("passed")
            end
        }
    }



=== TEST 22: clear file
--- exec
echo '' > ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr//



=== TEST 23: set route to an upstream returning 4xx
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
                    "uri": "/specific_status"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 24: trigger an upstream 404
--- exec
curl -s -H "X-Test-Upstream-Status: 404" http://127.0.0.1:1984/specific_status
--- wait: 5
--- response_body
upstream status: 404



=== TEST 25: verify 4xx marks the client span as error
--- config
    location /t {
        content_by_lua_block {
            local otel = require("lib.test_otel")

            local spans, err = otel.find_spans("ci/pod/otelcol-contrib/data-otlp.json",
                                               "apisix.upstream")
            if not spans then
                ngx.say("FAIL: ", err)
                return
            end
            if #spans ~= 1 then
                ngx.say("FAIL: expected 1 upstream span, got ", #spans)
                return
            end

            local span = spans[1]
            local attrs = otel.get_attr_map(span)
            if tostring(attrs["http.response.status_code"]) ~= "404" then
                ngx.say("FAIL: status ", tostring(attrs["http.response.status_code"]))
            elseif not (span.status and span.status.code == 2) then
                ngx.say("FAIL: 4xx should mark the client span as error")
            else
                ngx.say("passed")
            end
        }
    }
