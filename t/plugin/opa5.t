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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
plugins:
    - opa
    - opentelemetry
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);

    # mock OPA: deny and echo back the traceparent header it received
    my $config = $block->config // "";
    $config .= <<_EOC_;
    location /v1/data/mock {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.json.encode({result = {
                allow = false,
                reason = ngx.var.http_traceparent or "none",
            }}))
        }
    }
_EOC_
    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: setup route with opa
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:1984",
                                "policy": "mock"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: client traceparent is forwarded to OPA
--- request
GET /hello
--- more_headers
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
--- error_code: 403
--- response_body chomp
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01



=== TEST 3: no traceparent header is sent when there is none
--- request
GET /hello
--- error_code: 403
--- response_body chomp
none



=== TEST 4: setup route with opa and opentelemetry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                 ngx.HTTP_PUT,
                 [[{
                        "collector": {
                            "address": "127.0.0.1:4318"
                        }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:1984",
                                "policy": "mock"
                            },
                            "opentelemetry": {
                                "sampler": {
                                    "name": "always_off"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: OPA receives the APISIX span as parent, not the client one
--- request
GET /hello
--- more_headers
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
--- error_code: 403
--- response_body_like eval
qr/^00-0af7651916cd43dd8448eb211c80319c-(?!b7ad6b7169203331)[0-9a-f]{16}-0[01]$/
