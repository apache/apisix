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
BEGIN {
    sub set_env_from_file {
        my ($env_name, $file_path) = @_;

        open my $fh, '<', $file_path or die $!;
        my $content = do { local $/; <$fh> };
        close $fh;

        $ENV{$env_name} = $content;
    }
    # set env
    set_env_from_file('TEST_CERT', 't/certs/apisix.crt');
    set_env_from_file('TEST_KEY', 't/certs/apisix.key');
    set_env_from_file('TEST2_CERT', 't/certs/test2.crt');
    set_env_from_file('TEST2_KEY', 't/certs/test2.key');
}
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
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
                        }
                    },
                    "trace_id_source": "x-request-id"
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
--- request
GET /t



=== TEST 3: set ssl with two certs and keys in env
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                snis = {"test.com"},
                key =  "$env://TEST_KEY",
                cert = "$env://TEST_CERT",
                keys = {"$env://TEST2_KEY"},
                certs = {"$env://TEST2_CERT"}
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "snis": ["test.com"],
                        "key": "$env://TEST_KEY",
                        "cert": "$env://TEST_CERT",
                        "keys": ["$env://TEST2_KEY"],
                        "certs": ["$env://TEST2_CERT"]
                    },
                    "key": "/apisix/ssls/1"
                }]]
              )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: trigger SSL match with SNI
--- exec
curl -s -k --resolve "test.com:1994:127.0.0.1" https://test.com:1994/opentracing
--- wait: 5
--- response_body
opentracing



=== TEST 5: check create router span
--- exec
tail ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*create_router.*/



=== TEST 6: check sni_radixtree_match span
--- exec
tail ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*sni_radixtree_match.*/



=== TEST 7: route with one upstream node
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
                            "test1.com:1980": 1
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



=== TEST 8: hit route
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test1.com" then
            return {address = "127.0.0.2"}
        end

        error("unknown domain: " .. domain)
    end
--- request
GET /opentracing
--- response_body
opentracing



=== TEST 9: check resolve_dns span
--- exec
tail ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*resolve_dns.*/



=== TEST 10: check apisix.phase.delayed_body_filter.opentelemetry span
--- exec
tail ci/pod/otelcol-contrib/data-otlp.json
--- response_body eval
qr/.*apisix.phase.delayed_body_filter.opentelemetry.*/
