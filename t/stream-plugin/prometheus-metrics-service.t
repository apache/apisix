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

    # the endpoint serves a cache the privileged agent refills on this
    # interval, see t/stream-plugin/prometheus-metrics.t
    my $extra_yaml_config = <<_EOC_;
stream_plugins:
    - prometheus
plugin_attr:
    prometheus:
        refresh_interval: 0.5
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # see t/stream-plugin/prometheus-metrics.t: a scrape without the stream
    # block has no zone to read, and the reload into it drops the zone
    if ($block->request =~ m{/apisix/prometheus/metrics}) {
        $block->set_value("stream_enable", 1);
    }

    # an upstream that answers and then holds the session open, so that a
    # scrape can observe it while it is live. Only for the probes: a stream
    # block makes Test::Nginx install its own `location = /t`.
    if ($block->request =~ m{/probe}) {
        my $extra_stream_config = <<_EOC_;
server {
    listen 1993;
    content_by_lua_block {
        local sock = ngx.req.socket()
        sock:receive("1")
        ngx.say("hello world")
        ngx.flush(true)
        ngx.sleep(10)
    }
}
_EOC_

        $block->set_value("extra_stream_config", $extra_stream_config);
    }

    # The scrapes go over a raw socket: capturing into an APISIX route leaves
    # the upstream connect without a usable api_ctx.
    my $extra_init_by_lua = <<_EOC_;
    function _G.scrape()
        -- let the privileged agent refill the cache with what happened so far
        ngx.sleep(1.2)

        local sock = ngx.socket.tcp()
        local ok, err = sock:connect("127.0.0.1", 1984)
        if not ok then
            return nil, "scrape connect: " .. err
        end

        ok, err = sock:send("GET /apisix/prometheus/metrics HTTP/1.0\\r\\n"
                            .. "Host: 127.0.0.1\\r\\n\\r\\n")
        if not ok then
            return nil, "scrape send: " .. err
        end

        local body, rerr, partial = sock:receive("*a")
        sock:close()
        body = body or partial
        if not body then
            return nil, "scrape: " .. rerr
        end

        return body
    end

    -- Opens a session on 1985 and scrapes while it is live. A scrape runs
    -- first so that the bandwidth baselines are taken before the session
    -- exists: the first read of the zone only baselines what it finds.
    function _G.scrape_live_session()
        local body, err = scrape()
        if not body then
            return nil, err
        end

        local sock = ngx.socket.tcp()
        local ok
        ok, err = sock:connect("127.0.0.1", 1985)
        if not ok then
            return nil, "connect: " .. err
        end

        local bytes
        bytes, err = sock:send("hello")
        if not bytes then
            return nil, "send: " .. err
        end

        local line
        line, err = sock:receive("*l")
        if not line then
            return nil, "receive: " .. err
        end

        body, err = scrape()
        sock:close()
        return body, err
    end

    -- the value of the series whose labels are exactly `labels`
    function _G.series_value(body, name, labels)
        local prefix = name .. "{" .. labels .. "} "
        for line in body:gmatch("[^\\n]+") do
            if line:sub(1, #prefix) == prefix then
                return line:sub(#prefix + 1)
            end
        end
        return "no-series"
    end

    function _G.svc_a_ingress(body)
        return series_value(body, "apisix_stream_bandwidth",
            'listen_addr="0.0.0.0:1985",service="svc-a",service_id="svc-a",'
            .. 'type="ingress",side="downstream"')
    end

    function _G.active_on(body, service, service_id)
        return series_value(body, "apisix_stream_active_connections",
            'listen_addr="0.0.0.0:1985",service="' .. service
            .. '",service_id="' .. service_id .. '"')
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: pre-create the metrics endpoint, a service and a stream route under it
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
                    url = "/apisix/admin/services/svc-a",
                    data = [[{
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": [{
                                "host": "127.0.0.1",
                                "port": 1993,
                                "weight": 1
                            }]
                        }
                    }]]
                },
                {
                    url = "/apisix/admin/stream_routes/1",
                    data = [[{
                        "plugins": {
                            "prometheus": {}
                        },
                        "service_id": "svc-a"
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



=== TEST 2: a live session is split out under its service_id
The session is labelled in preread, so the service series carries it and the
unlabelled series of the same listen_addr does not. Like any zone slot, the
service's slot only takes a baseline the first time it is read, so its bytes
are counted from its second session on.
--- config
    location /probe {
        content_by_lua_block {
            -- the route from TEST 1 has to reach the stream workers first
            ngx.sleep(1.5)

            local body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end
            ngx.say("first session bandwidth=", svc_a_ingress(body))

            body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end

            ngx.say("service live=", active_on(body, "svc-a", "svc-a"))
            ngx.say("unlabelled live=", active_on(body, "", ""))

            local bw = tonumber(svc_a_ingress(body))
            ngx.say("service bandwidth=", bw and tonumber(bw) > 0 and "counted"
                                          or bw or "no-series")

            ngx.sleep(1.5)
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
first session bandwidth=no-series
service live=1
unlabelled live=0
service bandwidth=counted



=== TEST 3: once the session is gone its service gauge is back to zero
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_active_connections\{listen_addr="0\.0\.0\.0:1985",service="svc-a",service_id="svc-a"\} 0$/m
--- no_error_log
[error]



=== TEST 4: the service carries the gateway to upstream bytes
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",service="svc-a",service_id="svc-a",type="egress",side="upstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 5: the service carries the upstream to gateway bytes
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_bandwidth\{listen_addr="0\.0\.0\.0:1985",service="svc-a",service_id="svc-a",type="ingress",side="upstream"\} [1-9]\d*/
--- no_error_log
[error]



=== TEST 6: a route without a service keeps its sessions in the unlabelled total
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

            local body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end

            ngx.say("service live=", active_on(body, "svc-a", "svc-a"))
            ngx.say("unlabelled live=", active_on(body, "", ""))

            ngx.sleep(1.5)
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
service live=0
unlabelled live=1



=== TEST 7: with prefer_name the service label carries the name
The session is labelled when it starts, so the live session is already
reported under the name. The name is its own zone slot: the gauge left under
the id label by the earlier cases stays, at 0.
--- config
    location /probe {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t("/apisix/admin/services/svc-a", ngx.HTTP_PUT, [[{
                "name": "Order TCP",
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
                ngx.say("service: ", code)
                return
            end

            code = t("/apisix/admin/stream_routes/1", ngx.HTTP_PUT, [[{
                "plugins": {
                    "prometheus": {
                        "prefer_name": true
                    }
                },
                "service_id": "svc-a"
            }]])
            if code > 300 then
                ngx.say("route: ", code)
                return
            end

            ngx.sleep(1.5)

            -- the first session under the name only baselines its new slot
            local body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end

            body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end

            ngx.say("name live=", active_on(body, "Order TCP", "svc-a"))
            ngx.say("id label live=", active_on(body, "svc-a", "svc-a"))

            local bw = tonumber(series_value(body, "apisix_stream_bandwidth",
                'listen_addr="0.0.0.0:1985",service="Order TCP",service_id="svc-a",'
                .. 'type="ingress",side="downstream"'))
            ngx.say("name bandwidth=", bw and tonumber(bw) > 0 and "counted"
                                       or bw or "no-series")

            ngx.sleep(1.5)
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
name live=1
id label live=0
name bandwidth=counted



=== TEST 8: the termination status follows the same rule
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_stream_status\{code="200",listen_addr="0\.0\.0\.0:1985",service="Order TCP",service_id="svc-a",node="127\.0\.0\.1:1993"\} 2$/m
--- no_error_log
[error]



=== TEST 9: a slot that lost its baseline rebaselines instead of replaying
A baseline can go missing while the rest of the dict stays, when it is
evicted or could not be written. Counting that slot from zero would land its
whole lifetime total in one interval; it has to take a new baseline instead,
and later traffic is counted as usual.
--- config
    location /probe {
        content_by_lua_block {
            -- back to the id as the service label
            local t = require("lib.test_admin").test
            local code = t("/apisix/admin/services/svc-a", ngx.HTTP_PUT, [[{
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
                ngx.say("service: ", code)
                return
            end

            -- a series with a baseline behind it
            local body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end
            body, err = scrape()
            if not body then
                ngx.say(err)
                return
            end
            local before = tonumber(svc_a_ingress(body))

            ngx.shared["prometheus-metrics"]:delete(
                "stream_bytes_published:0.0.0.0:1985\31svc-a\31svc-a\31downstream_ingress")

            body, err = scrape()
            if not body then
                ngx.say(err)
                return
            end
            ngx.say("after the lost baseline: ", tonumber(svc_a_ingress(body)) == before)

            body, err = scrape_live_session()
            if not body then
                ngx.say(err)
                return
            end
            ngx.say("after one more session: +", tonumber(svc_a_ingress(body)) - before)

            ngx.sleep(1.5)
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
after the lost baseline: true
after one more session: +5



=== TEST 10: a session keeps the service label it started with
A route with an upstream_id and a service_id resolves its service name by
itself. The name picked when the session starts labels it in the zone and is
reused when it ends, so a rename while it is open does not split the session
between two names across the metrics.
--- config
    location /probe {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function put(uri, body)
                local code, res = t(uri, ngx.HTTP_PUT, body)
                if code > 300 then
                    ngx.say(uri, ": ", res)
                end
                return code <= 300
            end

            if not put("/apisix/admin/services/svc-b", [[{
                "name": "Billing",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": [{"host": "127.0.0.1", "port": 1993, "weight": 1}]
                }
            }]]) or not put("/apisix/admin/upstreams/up-1", [[{
                "type": "roundrobin",
                "nodes": [{"host": "127.0.0.1", "port": 1993, "weight": 1}]
            }]]) or not put("/apisix/admin/stream_routes/1", [[{
                "plugins": {
                    "prometheus": {
                        "prefer_name": true
                    }
                },
                "upstream_id": "up-1",
                "service_id": "svc-b"
            }]]) then
                return
            end

            ngx.sleep(1.5)

            local sock = ngx.socket.tcp()
            assert(sock:connect("127.0.0.1", 1985))
            assert(sock:send("hello"))
            assert(sock:receive("*l"))

            -- renamed while the session is open
            if not put("/apisix/admin/services/svc-b", [[{
                "name": "Billing v2",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": [{"host": "127.0.0.1", "port": 1993, "weight": 1}]
                }
            }]]) then
                return
            end
            ngx.sleep(1.5)

            assert(sock:close())

            local body, err = scrape()
            if not body then
                ngx.say(err)
                return
            end

            local status = 'code="200",listen_addr="0.0.0.0:1985",service="%s",'
                           .. 'service_id="svc-b",node="127.0.0.1:1993"'
            ngx.say("status under the first name: ",
                    series_value(body, "apisix_stream_status", status:format("Billing")))
            ngx.say("status under the new name: ",
                    series_value(body, "apisix_stream_status", status:format("Billing v2")))
        }
    }
--- request
GET /probe
--- stream_enable
--- timeout: 20
--- response_body
status under the first name: 1
status under the new name: no-series
