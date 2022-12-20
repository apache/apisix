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

    my $extra_yaml_config = <<_EOC_;
plugins:
    - example-plugin
    - key-auth
    - skywalking
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $extra_init_by_lua = <<_EOC_;
    -- reduce default report interval
    local client = require("skywalking.client")
    client.backendTimerDelay = 0.5

    local Span = require("skywalking.span")
    local old_f = Span.transform
    Span.transform = function (...)
        local args = {...}
        local span = args[1]
        ngx.log(ngx.WARN, "span peer: ", span.peer)
        return old_f(...)
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

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
                        "skywalking": {
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



=== TEST 2: trigger skywalking
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
span peer: 127.0.0.1:1980
--- wait: 1
