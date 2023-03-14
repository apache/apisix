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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
nginx_config:
  http_server_configuration_snippet: |
    set \$opentelemetry_context_traceparent ""
    set \$opentelemetry_trace_id ""
    set \$opentelemetry_span_id ""
  http:
    enable_access_log: true
    access_log: "/tmp/access.log"
    access_log_format: '{"timestamp": "\$time_iso8601","opentelemetry_context_traceparent": "\$opentelemetry_context_traceparent","opentelemetry_trace_id": "\$opentelemetry_trace_id","opentelemetry_span_id": "\$opentelemetry_span_id","remote_addr": "\$remote_addr","uri": "\$uri"}'
    access_log_format_escape: json
plugins:
    - opentelemetry
plugin_attr:
    opentelemetry:
        set_ngx_var: true
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

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
--- response_body
passed



=== TEST 2: trigger opentelemetry
--- request
GET /opentracing
--- access_log
--- response_body
opentracing
--- no_error_log
[error]



=== TEST 3: allow integer worker processes
--- config
    location /t {
        content_by_lua_block {
            local config = require("apisix.core").config.local_conf()
        }
    }
--- extra_yaml_config
nginx_config:
    
--- request
GET /t
--- response_body
1
