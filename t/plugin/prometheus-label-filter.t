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

=== TEST 1: setup routes
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {"prometheus": {}},
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {"public-api": {}},
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 2



=== TEST 2: pipeline of requests
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200]



=== TEST 3: default config - all standard labels present in http_status
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="\d+",route="1",matched_uri="[^"]*",matched_host="[^"]*",service="",consumer="",node="127\.0\.0\.1",request_type="[^"]*",request_llm_model="",llm_model=""\} \d+/



=== TEST 4: setup routes (disable_labels)
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable_labels:
                    - node
                    - consumer
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {"prometheus": {}},
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {"public-api": {}},
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 2



=== TEST 5: pipeline of requests (disable_labels)
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable_labels:
                    - node
                    - consumer
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200]



=== TEST 6: disable_labels - node and consumer absent, other labels intact
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable_labels:
                    - node
                    - consumer
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="\d+",route="1",matched_uri="[^"]*",matched_host="[^"]*",service="",request_type="[^"]*",request_llm_model="",llm_model=""\} \d+/



=== TEST 7: setup routes (disable http_status metric)
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable: true
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {"prometheus": {}},
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {"public-api": {}},
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
            }
            local t = require("lib.test_admin").test
            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 2



=== TEST 8: pipeline of requests (disable http_status)
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable: true
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200]



=== TEST 9: disable metric - http_status absent from output
--- yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
        metrics:
            http_status:
                disable: true
--- request
GET /apisix/prometheus/metrics
--- response_body_unlike eval
qr/apisix_http_status/
