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

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - http-logger
    - opentelemetry
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $upstream_server_config = $block->upstream_server_config // <<_EOC_;
    set \$opentelemetry_context_traceparent "";
    set \$opentelemetry_trace_id "";
    set \$opentelemetry_span_id "";
    access_log logs/error.log opentelemetry_log;
_EOC_

    $block->set_value("upstream_server_config", $upstream_server_config);

    my $http_config = $block->http_config // <<_EOC_;
    log_format opentelemetry_log '{"time": "\$time_iso8601","opentelemetry_context_traceparent": "\$opentelemetry_context_traceparent","opentelemetry_trace_id": "\$opentelemetry_trace_id","opentelemetry_span_id": "\$opentelemetry_span_id","remote_addr": "\$remote_addr","uri": "\$uri"}';
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
-- mock exporter http client
local client = require("opentelemetry.trace.exporter.http_client")
client.do_request = function()
    ngx.log(ngx.INFO, "opentelemetry export span")
    return "ok"
end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }


    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "opentelemetry_context_traceparent": "$opentelemetry_context_traceparent",
                        "opentelemetry_trace_id": "$opentelemetry_trace_id",
                        "opentelemetry_span_id": "$opentelemetry_span_id"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return body
            end

            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_PUT,
                [[{
                    "batch_span_processor": {
                        "max_export_batch_size": 1,
                        "inactive_timeout": 0.5
                    },
                    "set_ngx_var": true
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return body
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "http-logger": {
                                "uri": "http://127.0.0.1:1980/log",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "concat_method": "new_line"
                        },
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >=300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: trigger opentelemetry with open set variables
--- request
GET /hello
--- response_body
hello world
--- wait: 1
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span
--- error_log eval
qr/request log: \{.*"opentelemetry_context_traceparent":"00-\w{32}-\w{16}-01".*\}/



=== TEST 3: trigger opentelemetry with disable set variables
--- extra_yaml_config
plugins:
    - http-logger
    - opentelemetry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_PUT,
                [[{
                    "set_ngx_var": false
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return body
            end
        }
    }
--- request
GET /t



=== TEST 4: trigger opentelemetry with open set variables
--- request
GET /hello
--- response_body
hello world
--- wait: 1
--- error_log eval
qr/request log: \{.*"opentelemetry_context_traceparent":"".*\}/
