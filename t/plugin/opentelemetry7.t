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



=== TEST 2: set route
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



=== TEST 3: span:finish() errors must not break the request, for root and child spans
--- extra_init_by_lua
    -- simulate batch_span_processor failing in a restricted phase, e.g. the
    -- synchronous flush done when ngx.timer.at() fails during worker exit
    local bsp = require("opentelemetry.trace.batch_span_processor")
    bsp.on_end = function(self, span)
        ngx.log(ngx.INFO, "mock on_end called for span: ", span.name)
        error("API disabled in the context of log_by_lua*")
    end
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
mock on_end called for span: apisix.phase.access
failed to finish opentelemetry span, ignore error
--- no_error_log
[error]
failed to run log_by_lua*
