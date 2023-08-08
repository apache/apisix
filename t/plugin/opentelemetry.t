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
log_level("debug");

run_tests;

__DATA__

=== TEST 1: add plugin
--- extra_yaml_config
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
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
