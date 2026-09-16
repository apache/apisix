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
        $block->set_value("yaml_config", <<'EOC');
plugin_attr:
    prometheus:
        refresh_interval: 0.1
EOC
    }
});

run_tests;

__DATA__

=== TEST 1: set up the metrics route and a websocket-enabled route that logs $request_type
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

            local code, body = t('/apisix/admin/routes/ws',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {},
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": [
                                "return function(conf, ctx) ngx.log(ngx.WARN, \"request_type=\", ngx.var.request_type) end"
                            ]
                        }
                    },
                    "enable_websocket": true,
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/websocket_handshake"
                }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: a completed upgrade is logged as request_type=websocket
--- config
    location /t {
        content_by_lua_block {
            local client = require("resty.websocket.client")
            local wb = client:new()
            local ok, err = wb:connect("ws://127.0.0.1:1984/websocket_handshake")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data, typ, err = wb:recv_frame()
            if not data then
                ngx.say("failed to receive frame: ", err)
                return
            end

            wb:close()
            ngx.say("received: ", data, " (", typ, ")")
        }
    }
--- response_body
received: hello (text)
--- error_log
request_type=websocket



=== TEST 3: the session's status is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="101",route="ws",[^}]*request_type="websocket"[^}]*\} 1\n/



=== TEST 4: the session's latency is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_count\{type="request",route="ws",[^}]*request_type="websocket"[^}]*\} 1\n/



=== TEST 5: the session's bandwidth is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="ingress",route="ws",[^}]*request_type="websocket"[^}]*\} \d+\n/



=== TEST 6: a refused handshake on the same route stays request_type=traditional_http
--- request
GET /websocket_handshake
--- error_code: 400
--- error_log
failed to new websocket: bad "upgrade" request header
request_type=traditional_http



=== TEST 7: the refused request lands in its own series
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="400",route="ws",[^}]*request_type="traditional_http"[^}]*\} 1\n/



=== TEST 8: the websocket series is untouched by the refused request
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_http_latency_count\{type="request",route="ws",[^}]*request_type="websocket"[^}]*\} 1\n/
--- response_body_unlike eval
qr/apisix_http_latency_count\{type="request",route="ws",[^}]*request_type="websocket"[^}]*\} 2\n/



=== TEST 9: set up a websocket route whose proxy-rewrite reads $request_type before the upgrade
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/ws-cached',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {},
                        "proxy-rewrite": {
                            "uri": "/websocket_handshake",
                            "headers": {
                                "set": {"X-Request-Type": "$request_type"}
                            }
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": [
                                "return function(conf, ctx) ngx.log(ngx.WARN, \"x_request_type=\", ngx.var.http_x_request_type, \" ngx.var.request_type=\", ngx.var.request_type, \" ctx.var.request_type=\", ctx.var.request_type) end"
                            ]
                        }
                    },
                    "enable_websocket": true,
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/websocket_cached"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: the early read does not pin the session to traditional_http in either view
--- config
    location /t {
        content_by_lua_block {
            local client = require("resty.websocket.client")
            local wb = client:new()
            local ok, err = wb:connect("ws://127.0.0.1:1984/websocket_cached")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data, typ, err = wb:recv_frame()
            if not data then
                ngx.say("failed to receive frame: ", err)
                return
            end

            wb:close()
            ngx.say("received: ", data, " (", typ, ")")
        }
    }
--- response_body
received: hello (text)
--- error_log
x_request_type=traditional_http ngx.var.request_type=websocket ctx.var.request_type=websocket



=== TEST 11: the status of the early-read session is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_status\{code="101",route="ws-cached",[^}]*request_type="websocket"[^}]*\} 1\n/



=== TEST 12: the latency of the early-read session is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_http_latency_count\{type="request",route="ws-cached",[^}]*request_type="websocket"[^}]*\} 1\n/



=== TEST 13: the bandwidth of the early-read session is labelled request_type=websocket
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="ingress",route="ws-cached",[^}]*request_type="websocket"[^}]*\} \d+\n/
