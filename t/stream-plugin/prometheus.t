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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = <<_EOC_;
stream_plugins:
    - mqtt-proxy
    - prometheus
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: pre-create public API route
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
                {
                    url = "/apisix/admin/stream_routes/mqtt",
                    data = [[{
                        "plugins": {
                            "mqtt-proxy": {
                                "protocol_name": "MQTT",
                                "protocol_level": 4
                            },
                            "prometheus": {}
                        },
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": [{
                                "host": "127.0.0.1",
                                "port": 1995,
                                "weight": 1
                            }]
                        }
                    }]]
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                if code > 300 then
                    ngx.say(body)
                    return
                end
            end
        }
    }
--- response_body



=== TEST 2: hit
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- stream_response
hello world



=== TEST 3: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_stream_connection_total\{route="mqtt"\} 1/



=== TEST 4: hit, error
--- stream_request eval
mmm
--- error_log
Received unexpected MQTT packet type+flags



=== TEST 5: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_stream_connection_total\{route="mqtt"\} 2/



=== TEST 6: contains metrics from stub_status
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_nginx_http_current_connections\{state="active"\} 1/



=== TEST 7: contains basic metrics
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_node_info\{hostname="[^"]+"\}/
