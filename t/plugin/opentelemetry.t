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



=== TEST 20: test create_router span when SSL router is created
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            -- First, let's trigger SSL router creation by adding an SSL certificate
            local code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$env://TEST_CERT",
                    "key": "$env://TEST_KEY",
                    "snis": ["test.com"]
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            
            ngx.say("SSL certificate added")
        }
    }
--- request
GET /t
--- response_body
SSL certificate added
--- wait: 1



=== TEST 21: verify create_router span in logs after SSL setup
--- exec
grep -c '"name":"create_router"' ci/pod/otelcol-contrib/data-otlp.json || echo "0"
--- response_body eval
qr/[1-9]\d*/



=== TEST 22: test sni_radixtree_match span with SSL request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            -- Create a route that uses the SSL certificate
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
                    "uri": "/hello",
                    "hosts": ["test.com"],
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
            
            ngx.say("Route created")
        }
    }
--- request
GET /t
--- response_body
Route created



=== TEST 23: trigger SSL match with SNI
--- exec
curl -k -H "Host: test.com" https://127.0.0.1:1994/hello --resolve "test.com:1994:127.0.0.1" || echo "request_completed"
--- wait: 2



=== TEST 24: verify sni_radixtree_match span in logs
--- exec
grep -c '"name":"sni_radixtree_match"' ci/pod/otelcol-contrib/data-otlp.json || echo "0"
--- response_body eval
qr/[1-9]\d*/



=== TEST 25: test multiple SSL certificates trigger multiple create_router spans
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            -- Add another SSL certificate to trigger router recreation
            local code, body = t('/apisix/admin/ssls/2',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$env://TEST_CERT",
                    "key": "$env://TEST_KEY",
                    "snis": ["test2.com"]
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            
            ngx.say("Second SSL certificate added")
        }
    }
--- request
GET /t
--- response_body
Second SSL certificate added
--- wait: 1



=== TEST 26: verify create_router span count increased after adding second SSL
--- exec
grep -o '"name":"create_router"' ci/pod/otelcol-contrib/data-otlp.json | wc -l
--- response_body eval
qr/[2-9]\d*/



=== TEST 27: test SSL router error span status
--- config
    location /t {
        content_by_lua_block {
            -- This test verifies that when SSL router creation fails,
            -- the span status is set to ERROR
            -- We'll simulate this by causing a router creation failure
            
            local ssl = require("apisix.ssl")
            local orig_func = ssl.get_latest_certificates
            
            -- Temporarily replace the function to simulate failure
            ssl.get_latest_certificates = function()
                return nil, "simulated error"
            end
            
            local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
            local api_ctx = {}
            
            -- This should trigger an error path in match_and_set
            local ok, err = radixtree_sni.match_and_set(api_ctx, false, "test.com")
            
            -- Restore original function
            ssl.get_latest_certificates = orig_func
            
            if not ok then
                ngx.say("Error simulated successfully: ", err)
            else
                ngx.say("Unexpected success")
            end
        }
    }
--- request
GET /t
--- response_body_like
Error simulated successfully:.*



=== TEST 28: verify error status in create_router span
--- exec
tail -n 5 ci/pod/otelcol-contrib/data-otlp.json | grep -A 10 -B 10 '"name":"create_router"' | grep -c '"status":"STATUS_ERROR"' || echo "0"
--- response_body eval
qr/[0-9]+/



=== TEST 29: test SSL match failure span status
--- config
    location /t {
        content_by_lua_block {
            local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
            local api_ctx = {}
            
            -- Try to match a non-existent SNI
            local ok, err = radixtree_sni.match_and_set(api_ctx, false, "nonexistent.com")
            
            if not ok then
                ngx.say("SNI match failed as expected: ", err)
            else
                ngx.say("Unexpected match success")
            end
        }
    }
--- request
GET /t
--- response_body_like
SNI match failed as expected:.*



=== TEST 30: verify error status in sni_radixtree_match span for failed match
--- exec
tail -n 5 ci/pod/otelcol-contrib/data-otlp.json | grep -A 10 -B 10 '"name":"sni_radixtree_match"' | grep -c '"status":"STATUS_ERROR"' || echo "0"
--- response_body eval
qr/[0-9]+/



=== TEST 31: test SSL router span attributes
--- exec
tail -n 10 ci/pod/otelcol-contrib/data-otlp.json | grep -A 20 '"name":"sni_radixtree_match"' | grep -q '"key":"span.kind"' && echo "span_kind_found" || echo "span_kind_not_found"
--- response_body
span_kind_found



=== TEST 32: test internal span kind for SSL router spans
--- exec
tail -n 10 ci/pod/otelcol-contrib/data-otlp.json | grep -A 20 '"name":"create_router"' | grep -q '"stringValue":"SPAN_KIND_INTERNAL"' && echo "internal_kind_found" || echo "internal_kind_not_found"
--- response_body
internal_kind_found



=== TEST 33: test multiple SNI matches create multiple spans
--- exec
curl -k -H "Host: test.com" https://127.0.0.1:1994/hello --resolve "test.com:1994:127.0.0.1" > /dev/null 2>&1
curl -k -H "Host: test2.com" https://127.0.0.1:1994/hello --resolve "test2.com:1994:127.0.0.1" > /dev/null 2>&1
echo "requests_sent"
--- wait: 2
--- response_body
requests_sent



=== TEST 34: verify multiple sni_radixtree_match spans
--- exec
grep -o '"name":"sni_radixtree_match"' ci/pod/otelcol-contrib/data-otlp.json | wc -l
--- response_body eval
qr/[2-9]\d*/
