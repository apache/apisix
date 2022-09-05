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
plugins:
    - example-plugin
    - key-auth
    - opentelemetry
plugin_attr:
    opentelemetry:
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }


    if (!$block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
-- mock exporter http client
local client = require("opentelemetry.trace.exporter.http_client")
client.do_request = function()
    ngx.log(ngx.INFO, "opentelemetry export span")
end
local ctx_new = require("opentelemetry.context").new
require("opentelemetry.context").new = function (...)
    local ctx = ctx_new(...)
    local current = ctx.current
    ctx.current = function (...)
        ngx.log(ngx.INFO, "opentelemetry context current")
        return current(...)
    end
    return ctx
end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: trace request rejected by auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
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
                    "plugins": {
                        "key-auth": {},
                        "example-plugin": {"i": 1},
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



=== TEST 2: trigger opentelemetry
--- request
GET /hello
--- error_code: 401
--- wait: 1
--- grep_error_log eval
qr/(opentelemetry export span|opentelemetry context current|plugin body_filter phase)/
--- grep_error_log_out
plugin body_filter phase
plugin body_filter phase
opentelemetry context current
opentelemetry context current
opentelemetry export span



=== TEST 3: set additional_attributes with match
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
                            },
                            "additional_header_prefix_attributes": [
                                "x-my-header-*"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/attributes"
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



=== TEST 4: opentelemetry expands headers
--- extra_init_by_lua
    local otlp = require("opentelemetry.trace.exporter.otlp")
    otlp.export_spans = function(self, spans)
        if (#spans ~= 1) then
            ngx.log(ngx.ERR, "unexpected spans length: ", #spans)
            return
        end

        local attributes_names = {}
        local attributes = {}
        local span = spans[1]
        for _, attribute in ipairs(span.attributes) do
            if attribute.key == "hostname" then
                -- remove any randomness
                goto skip
            end
            table.insert(attributes_names, attribute.key)
            attributes[attribute.key] = attribute.value.string_value or ""
            ::skip::
        end
        table.sort(attributes_names)
        for _, attribute in ipairs(attributes_names) do
            ngx.log(ngx.INFO, "attribute " .. attribute .. ": \"" .. attributes[attribute] .. "\"")
        end

        ngx.log(ngx.INFO, "opentelemetry export span")
    end
--- request
GET /attributes
--- more_headers
x-my-header-name: william
x-my-header-nick: bill
--- wait: 1
--- error_code: 404
--- grep_error_log eval
qr/attribute .+?:.[^,]*/
--- grep_error_log_out
attribute route: "route_name"
attribute service: ""
attribute x-my-header-name: "william"
attribute x-my-header-nick: "bill"
