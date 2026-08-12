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

    # stream_plugins replaces the default list rather than extending it, so
    # every plugin these tests touch has to be named here
    my $extra_yaml_config = <<_EOC_;
stream_plugins:
    - prometheus
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # Every scrape needs the stream block in its own config. The zone backing
    # the bandwidth and active connection metrics is declared there and is read
    # while the exposition is built, so a block generated without a stream
    # block has nothing to read -- and the reload into it drops the zone, which
    # takes the running totals with it.
    if ($block->request =~ m{/apisix/prometheus/metrics}) {
        $block->set_value("stream_enable", 1);
    }
});

run_tests;

__DATA__

=== TEST 1: pre-create the metrics endpoint and a stream route
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
                    url = "/apisix/admin/stream_routes/1",
                    data = [[{
                        "plugins": {
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



=== TEST 2: proxy a session
--- stream_request
hello
--- stream_response
hello world



=== TEST 3: the session is counted as a normal close, not as an error
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_stream_status\{code="200",listen_addr="[^"]+",node="127.0.0.1:1995"\} 1$/m



=== TEST 4: bandwidth and active connections come from the nginx zone
The zone is read while the metrics endpoint is served, so a session that is
still open has to show up in that same scrape.

The upstream has to stay open after answering: the shared fake upstreams close
as soon as they have written their line, and nginx finalizes the session on the
upstream's EOF no matter that the client is still connected -- which is why the
gauge would read 0 while the probe believes its session is live.

The probe cannot live at /t: with the stream subsystem enabled Test::Nginx
installs its own `location = /t`, and an exact match wins.
--- extra_stream_config
server {
    listen 1993;
    content_by_lua_block {
        local sock = ngx.req.socket()
        sock:receive("1")
        ngx.say("hello world")
        ngx.flush(true)
        -- answer, then hold the session open for the probe to observe
        ngx.sleep(10)
    }
}
--- config
    location /probe {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t("/apisix/admin/stream_routes/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "prometheus": {}
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": [{
                        "host": "127.0.0.1",
                        "port": 1993,
                        "weight": 1
                    }]
                }
            }]])
            if code > 300 then
                ngx.say("route: ", code)
                return
            end

            ngx.sleep(1.5)

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.say("connect: ", err)
                return
            end

            local bytes
            bytes, err = sock:send("hello")
            if not bytes then
                ngx.say("send: ", err)
                return
            end

            -- the fake upstream answers with ngx.say, so the line is terminated
            local line
            line, err = sock:receive("*l")
            if not line then
                ngx.say("receive: ", err)
                return
            end

            -- The session is still open here, so this scrape has to report it.
            -- Raw socket rather than ngx.location.capture: capturing into an
            -- APISIX route leaves the upstream connect without a usable
            -- api_ctx.
            local scrape = ngx.socket.tcp()
            ok, err = scrape:connect("127.0.0.1", 1984)
            if not ok then
                ngx.say("scrape connect: ", err)
                return
            end

            ok, err = scrape:send("GET /apisix/prometheus/metrics HTTP/1.0\r\n"
                                  .. "Host: 127.0.0.1\r\n\r\n")
            if not ok then
                ngx.say("scrape send: ", err)
                return
            end

            local body, rerr, partial = scrape:receive("*a")
            scrape:close()
            body = body or partial
            if not body then
                ngx.say("scrape: ", rerr)
                return
            end

            local live = body:match('apisix_stream_active_connections'
                .. '{listen_addr="0%.0%.0%.0:1985"[^}]*} (%d+)')
            ngx.say("live=", live or "no-series")

            ok, err = sock:close()
            if not ok then
                ngx.say("close: ", err)
                return
            end

            ngx.sleep(1.5)
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
live=1



=== TEST 5: bandwidth for client to gateway
nginx-lua-prometheus sorts the exposition, so each series is asserted on its
own rather than in one order-dependent pattern.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",type="ingress",side="downstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 6: bandwidth for gateway to client
nginx-lua-prometheus sorts the exposition, so each series is asserted on its
own rather than in one order-dependent pattern.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",type="egress",side="downstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 7: bandwidth for gateway to upstream
nginx-lua-prometheus sorts the exposition, so each series is asserted on its
own rather than in one order-dependent pattern.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",type="egress",side="upstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 8: bandwidth for upstream to gateway
nginx-lua-prometheus sorts the exposition, so each series is asserted on its
own rather than in one order-dependent pattern.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",type="ingress",side="upstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 9: the gauge drops back to zero once the session is gone
TEST 4 asserted it reads 1 while its session is open; the probe then closed it
and outlived another tick, so the published value has to be 0 by now.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_active_connections\{listen_addr="0\.0\.0\.0:1985"\} 0$/m
--- no_error_log
[error]



=== TEST 10: an unreachable upstream is counted as 502
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/stream_routes/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "prometheus": {}
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": [{
                        "host": "127.0.0.1",
                        "port": 1979,
                        "weight": 1
                    }]
                }
            }]])
            if code > 300 then
                ngx.say(body)
                return
            end
        }
    }
--- response_body



=== TEST 11: hit the unreachable upstream
--- stream_request
hello
--- error_log
connect() failed



=== TEST 12: the failing node is still reported on a 502
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_stream_status\{code="502",listen_addr="[^"]+",node="127.0.0.1:1979"\} 1$/m



=== TEST 13: point a route at an upstream that accepts and then says nothing
--- extra_stream_config
server {
    listen 1993;
    content_by_lua_block {
        -- accept and stay silent, so the session dies on proxy_timeout
        ngx.sleep(5)
    }
}
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/stream_routes/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "prometheus": {}
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": [{
                        "host": "127.0.0.1",
                        "port": 1993,
                        "weight": 1
                    }]
                }
            }]])
            if code > 300 then
                ngx.say(body)
                return
            end
        }
    }
--- response_body



=== TEST 14: let a session die on the idle timeout
--- extra_stream_config
server {
    listen 1993;
    content_by_lua_block {
        ngx.sleep(5)
    }
}
--- stream_server_config
    proxy_timeout 500ms;
    preread_by_lua_block {
        apisix.stream_preread_phase()
    }
    proxy_pass apisix_backend;
--- stream_request
hello
--- timeout: 10



=== TEST 15: nginx calls that session a 200, the metric must not
This is the point of the feature. nginx reports $status 200 for every failure
after the upstream connection is up -- apisix-nginx-module's t/stream/metrics.t
pins that for the same case -- so an idle timeout has to reach the metric as
502 through $stream_session_reason, not as a success.
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_status\{code="502",listen_addr="0\.0\.0\.0:1985",node="127\.0\.0\.1:1993"\}/
--- no_error_log
[error]
