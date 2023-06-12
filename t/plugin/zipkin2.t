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

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /echo");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $extra_init_by_lua = <<_EOC_;
    local new = require("opentracing.tracer").new
    local tracer_mt = getmetatable(new()).__index
    local orig_func = tracer_mt.start_span
    tracer_mt.start_span = function (...)
        local orig = orig_func(...)
        local mt = getmetatable(orig).__index
        local old_start_child_span = mt.start_child_span
        mt.start_child_span = function(self, name, time)
            ngx.log(ngx.WARN, "zipkin start_child_span ", name, " time: ", time)
            return old_start_child_span(self, name, time)
        end
        return orig
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

});

run_tests;

__DATA__

=== TEST 1: b3 single header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9999/mock_zipkin",
                                "sample_ratio": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 2: sanity
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-1-05e3ac9a4f6e3b90
--- response_headers
x-b3-sampled: 1
x-b3-traceid: 80f198ee56343ba864fe8b2a57d3eff7
--- raw_response_headers_unlike
b3:
--- error_log
new span context: trace id: 80f198ee56343ba864fe8b2a57d3eff7, span id: e457b5a2e4d86bd1, parent span id: 05e3ac9a4f6e3b90
--- grep_error_log eval
qr/zipkin start_child_span apisix.response_span time: nil/
--- grep_error_log_out



=== TEST 3: invalid header
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7
--- response_headers
x-b3-sampled:
--- error_code: 400
--- error_log
invalid b3 header



=== TEST 4: disable via b3
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-0-05e3ac9a4f6e3b90
--- response_headers_like
x-b3-sampled: 0
x-b3-traceid: 80f198ee56343ba864fe8b2a57d3eff7
x-b3-parentspanid: e457b5a2e4d86bd1
x-b3-spanid: \w+



=== TEST 5: disable via b3 (abbr)
--- more_headers
b3: 0
--- response_headers_like
x-b3-sampled: 0
x-b3-spanid: \w+
x-b3-traceid: \w+



=== TEST 6: debug via b3
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-d-05e3ac9a4f6e3b90
--- response_headers
x-b3-sampled: 1
x-b3-flags: 1



=== TEST 7: b3 without parent span id
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-d
--- response_headers
x-b3-sampled: 1
x-b3-flags: 1
--- error_log
new span context: trace id: 80f198ee56343ba864fe8b2a57d3eff7, span id: e457b5a2e4d86bd1, parent span id: nil



=== TEST 8: b3 without sampled & parent span id
--- more_headers
b3: 80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1
--- response_headers
x-b3-sampled: 1
--- error_log
new span context: trace id: 80f198ee56343ba864fe8b2a57d3eff7, span id: e457b5a2e4d86bd1, parent span id: nil



=== TEST 9: set plugin with span version 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1980/mock_zipkin?span_version=1",
                                "sample_ratio": 1,
                                "service_name": "apisix",
                                "span_version": 1
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



=== TEST 10: tiger zipkin
--- request
GET /opentracing
--- wait: 10
--- grep_error_log eval
qr/zipkin start_child_span apisix.response_span time: nil/
--- grep_error_log_out



=== TEST 11: check not error with limit count
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9999/mock_zipkin",
                                "sample_ratio": 1,
                                "service_name": "APISIX"
                            },
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 403,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /t", "GET /opentracing", "GET /opentracing", "GET /opentracing"]
--- error_code eval
[200, 200, 200, 403]
