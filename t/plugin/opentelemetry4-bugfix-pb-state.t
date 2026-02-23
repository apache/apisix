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
    - opentelemetry
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
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
                    "trace_id_source": "x-request-id",
                    "collector": {
                        "address": "127.0.0.1:4318",
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
                        }
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
--- response_body
passed



=== TEST 2: set additional_attributes with match
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
                    "uri": "/hello"
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



=== TEST 3: opentelemetry expands headers
--- extra_init_by_lua
    local otlp = require("opentelemetry.trace.exporter.otlp")
    local orig_export_spans = otlp.export_spans
    otlp.export_spans = function(self, spans)
        if (#spans ~= 1) then
            ngx.log(ngx.ERR, "unexpected spans length: ", #spans)
            return
        end

        local attributes_names = {}
        local attributes = {}
        local span = spans[1]
        for _, attribute in ipairs(span.attributes) do
            table.insert(attributes_names, attribute.key)
            attributes[attribute.key] = attribute.value.string_value or ""
            ::skip::
        end
        table.sort(attributes_names)
        for _, attribute in ipairs(attributes_names) do
            ngx.log(ngx.INFO, "attribute " .. attribute .. ": \"" .. attributes[attribute] .. "\"")
        end

        ngx.log(ngx.INFO, "opentelemetry export span")
        return orig_export_spans(self, spans)
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/protos/1',
                 ngx.HTTP_PUT,
                 [[{
                    "content" : "syntax = \"proto3\";
                      package helloworld;
                      service Greeter {
                          rpc SayHello (HelloRequest) returns (HelloReply) {}
                      }
                      message HelloRequest {
                          string name = 1;
                      }
                      message HelloReply {
                          string message = 1;
                         }"
                   }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            local http = require "resty.http"
            local httpc = http.new()
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local headers = {
                ["x-my-header-name"] = "william",
                ["x-my-header-nick"] = "bill",
            }
            local res, err = httpc:request_uri(uri1, {method = "GET", headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- request
GET /t
--- wait: 1
--- error_code: 200
--- no_error_log
type 'opentelemetry.proto.trace.v1.TracesData' does not exists
--- grep_error_log eval
qr/attribute (apisix|x-my).+?:.[^,]*/
--- grep_error_log_out
attribute apisix.route_id: "1"
attribute apisix.route_name: "route_name"
attribute x-my-header-name: "william"
attribute x-my-header-nick: "bill"
