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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set route with prometheus ttl
--- yaml_config
plugin_attr:
    prometheus:
        default_buckets:
            - 15
            - 55
            - 105
            - 205
            - 505
        metrics:
            http_status:
                expire: 1
            http_latency:
                expire: 1
            bandwidth:
                expire: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/prometheus/metrics"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "prometheus": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local code, body = t('/hello1',
                ngx.HTTP_GET,
                "",
                nil,
                nil
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(2)
            local code, pass, body = t('/apisix/prometheus/metrics',
                ngx.HTTP_GET,
                "",
                nil,
                nil
            )

            local metrics_to_check = {"apisix_bandwidth", "http_latency", "http_status",}

            -- verify that above mentioned metrics are not in the metrics response
            for _, v in pairs(metrics_to_check) do
                local match, err = ngx.re.match(body, "\\b" .. v .. "\\b", "m")
                if match then
                    ngx.status = 500
                    ngx.say("error found " .. v .. " in metrics")
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: expired entries are reclaimed in bounded batches
--- config
    location /t {
        content_by_lua_block {
            local exporter = require("apisix.plugins.prometheus.exporter")
            local dict = ngx.shared["prometheus-metrics"]

            -- a permanent entry kept at the LRU tail stops the passive
            -- per-write expiry scan, which is what lets expired entries pile
            -- up in the first place
            dict:set("flush_expired_tail", 1)
            for i = 1, 20000 do
                dict:set("flush_expired_" .. i, "v", 0.1)
            end
            ngx.sleep(0.2)

            -- more than one batch, so the loop has to run again after the
            -- delay instead of stopping at the first batch
            local freed = exporter.flush_expired_metrics()
            ngx.say("reclaimed all: ", freed >= 20000)
            ngx.say("left over: ", exporter.flush_expired_metrics())
            ngx.say("tail kept: ", dict:get("flush_expired_tail"))
        }
    }
--- response_body
reclaimed all: true
left over: 0
tail kept: 1
