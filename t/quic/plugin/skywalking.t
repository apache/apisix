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

    local sw_tracer = require("skywalking.tracer")
    local inject = function(mod, name)
        local old_f = mod[name]
        mod[name] = function (...)
            ngx.log(ngx.WARN, "skywalking run ", name)
            return old_f(...)
        end
    end

    inject(sw_tracer, "start")
    inject(sw_tracer, "finish")
    inject(sw_tracer, "prepareForReport")
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

=== TEST 1:  create ssl for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
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



=== TEST 2: add plugin
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



=== TEST 3: trigger skywalking
--- exec
curl -k -v -H "Host: test.com" -H "content-length: 0" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/opentracing 2>&1 | cat
--- response_body_like
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out
skywalking run start
skywalking run finish
skywalking run prepareForReport
--- wait: 1
