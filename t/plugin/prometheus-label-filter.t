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

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'EOF');
plugin_attr:
    prometheus:
        refresh_interval: 0.1
EOF
    }
});

run_tests;

__DATA__

=== TEST 1: set up routes and disable labels per-metric via plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {"public-api": {}},
                    "uri": "/apisix/prometheus/metrics"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to create metrics route")
                return
            end

            code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {"prometheus": {}},
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to create route 1")
                return
            end

            local code, body = t('/apisix/admin/plugin_metadata/prometheus',
                ngx.HTTP_PUT,
                [[{
                    "disabled_labels": {
                        "http_status": ["route", "node"],
                        "bandwidth": ["node"]
                    }
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- give the data plane time to sync the routes and plugin metadata
            ngx.sleep(1.5)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: warm up metrics with client requests
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200]



=== TEST 3: http_status has disabled labels (route, node) collapsed to ""
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="\d+",route="",matched_uri="[^"]*",matched_host="[^"]*",service="[^"]*",consumer="[^"]*",node="",request_type="[^"]*",request_llm_model="[^"]*",llm_model="[^"]*",response_source="[^"]*"\} \d+/



=== TEST 4: per-metric scoping - http_latency keeps route and node populated
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_count\{type="request",route="1",service="[^"]*",consumer="[^"]*",node="127.0.0.1",request_type="[^"]*",request_llm_model="[^"]*",llm_model="[^"]*"\} \d+/



=== TEST 5: per-metric scoping - bandwidth collapses node but keeps route
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="(?:ingress|egress)",route="1",service="[^"]*",consumer="[^"]*",node="",request_type="[^"]*",request_llm_model="[^"]*",llm_model="[^"]*"\} \d+/



=== TEST 6: reject disabling a structural label (`code` on http_status)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/prometheus',
                ngx.HTTP_PUT,
                [[{"disabled_labels": {"http_status": ["code"]}}]])
            ngx.say(body)
        }
    }
--- response_body eval
qr/failed to validate item 1/



=== TEST 7: reject an unknown metric key (additionalProperties = false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/prometheus',
                ngx.HTTP_PUT,
                [[{"disabled_labels": {"unknown_metric": ["node"]}}]])
            ngx.say(body)
        }
    }
--- response_body eval
qr/additional properties forbidden/
