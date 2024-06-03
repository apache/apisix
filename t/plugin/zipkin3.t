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
    - zipkin
plugin_attr:
    zipkin:
        set_ngx_var: true
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $upstream_server_config = $block->upstream_server_config // <<_EOC_;
        set \$zipkin_context_traceparent "";
        set \$zipkin_trace_id "";
        set \$zipkin_span_id "";
_EOC_

    $block->set_value("upstream_server_config", $upstream_server_config);

    my $extra_init_by_lua = <<_EOC_;
    local zipkin = require("apisix.plugins.zipkin")
    local orig_func = zipkin.access
    zipkin.access = function (...)
        local traceparent = ngx.var.zipkin_context_traceparent
        if traceparent == nil or traceparent == '' then
           ngx.log(ngx.ERR,"ngx_var.zipkin_context_traceparent is empty")
        else
            ngx.log(ngx.ERR,"ngx_var.zipkin_context_traceparent:",ngx.var.zipkin_context_traceparent)
        end

        local orig = orig_func(...)
        return orig
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

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



=== TEST 2:  trigger zipkin with open set variables
--- request
GET /echo
--- error_log eval
qr/ngx_var.zipkin_context_traceparent:00-\w{32}-\w{16}-01*/



=== TEST 3: trigger zipkin with disable set variables
--- extra_yaml_config
plugins:
    - zipkin
plugin_attr:
    zipkin:
        set_ngx_var: false
--- request
GET /echo
--- error_log
ngx_var.zipkin_context_traceparent is empty
