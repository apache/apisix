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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set upstream with slow_start
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 300,
                        "min_weight_percent": 1
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: defaults are filled in by the schema
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local conf = {
                type = "roundrobin",
                nodes = {{host = "127.0.0.1", port = 1980, weight = 100}},
                slow_start = {
                    slow_start_time_seconds = 300,
                    min_weight_percent = 1,
                },
            }

            local ok, err = core.schema.check(core.schema.upstream, conf)
            if not ok then
                ngx.say("failed: ", err)
                return
            end

            ngx.say("interval: ", conf.slow_start.interval,
                    ", aggression: ", conf.slow_start.aggression,
                    ", startup_grace_period_seconds: ",
                    conf.slow_start.startup_grace_period_seconds)
        }
    }
--- response_body
interval: 1, aggression: 1, startup_grace_period_seconds: 0



=== TEST 3: all fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 300,
                        "min_weight_percent": 20,
                        "interval": 5,
                        "aggression": 2.5,
                        "startup_grace_period_seconds": 180
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 4: slow_start_time_seconds is required
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "min_weight_percent": 1
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/property .*slow_start_time_seconds.* is required/



=== TEST 5: min_weight_percent is required
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 10
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/property .*min_weight_percent.* is required/



=== TEST 6: min_weight_percent is a percentage, not a ratio
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, percent in ipairs({0, 101}) do
                local code, body = t('/apisix/admin/upstreams/2',
                    ngx.HTTP_PUT,
                    [[{
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ],
                        "slow_start": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": ]] .. percent .. [[
                        }
                    }]]
                )
                if code < 300 then
                    ngx.say("unexpectedly accepted min_weight_percent ", percent)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: reject slow_start_time_seconds below 1 and aggression below 0.01
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cases = {
                [["slow_start_time_seconds": 0, "min_weight_percent": 1]],
                [["slow_start_time_seconds": 10, "min_weight_percent": 1, "aggression": 0]],
                [["slow_start_time_seconds": 10, "min_weight_percent": 1, "interval": 0]],
                [["slow_start_time_seconds": 10, "min_weight_percent": 1, "default_weight": 0]],
                [["slow_start_time_seconds": 10, "min_weight_percent": 1,
                  "startup_grace_period_seconds": -1]],
                [["slow_start_time_seconds": 10, "min_weight_percent": 1, "unknown": 1]],
            }

            for i, case in ipairs(cases) do
                local code, body = t('/apisix/admin/upstreams/2',
                    ngx.HTTP_PUT,
                    [[{
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ],
                        "slow_start": {]] .. case .. [[}
                    }]]
                )
                if code < 300 then
                    ngx.say("unexpectedly accepted case ", i)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: reject slow_start on a non roundrobin upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "chash",
                    "key": "remote_addr",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 10,
                        "min_weight_percent": 1
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start is only supported by the roundrobin upstream type/



=== TEST 9: reject an interval longer than the slow start window
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 10,
                        "min_weight_percent": 1,
                        "interval": 11
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start.interval can't be greater than slow_start.slow_start_time_seconds/



=== TEST 10: reject nodes with different priorities
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100, "priority": 0},
                        {"host": "127.0.0.1", "port": 1981, "weight": 100, "priority": -1}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 10,
                        "min_weight_percent": 1
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start doesn't support an upstream with nodes of different priorities/



=== TEST 11: accept slow_start on a route embedded upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ],
                        "slow_start": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: accept slow_start on a service embedded upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ],
                        "slow_start": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 13: reject slow_start on a route embedded upstream that is not roundrobin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "least_conn",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ],
                        "slow_start": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": 1
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start is only supported by the roundrobin upstream type/



=== TEST 14: reject slow_start in a traffic-split upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "traffic-split": {
                            "rules": [{
                                "weighted_upstreams": [{
                                    "upstream": {
                                        "type": "roundrobin",
                                        "nodes": [
                                            {"host": "127.0.0.1", "port": 1981, "weight": 100}
                                        ],
                                        "slow_start": {
                                            "slow_start_time_seconds": 10,
                                            "min_weight_percent": 1
                                        }
                                    },
                                    "weight": 1
                                }]
                            }]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 100}
                        ]
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start is not supported by the upstream of the traffic-split plugin/



=== TEST 15: declarative validation accepts slow_start
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/configs/validate',
                ngx.HTTP_POST,
                [[{
                    "upstreams": [
                        {
                            "id": "u1",
                            "type": "roundrobin",
                            "nodes": {"127.0.0.1:1980": 1},
                            "slow_start": {
                                "slow_start_time_seconds": 10,
                                "min_weight_percent": 1
                            }
                        }
                    ]
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 200
--- response_body
passed



=== TEST 16: declarative validation still rejects an unusable slow_start
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/configs/validate',
                ngx.HTTP_POST,
                [[{
                    "upstreams": [
                        {
                            "id": "u1",
                            "type": "chash",
                            "key": "remote_addr",
                            "nodes": {"127.0.0.1:1980": 1},
                            "slow_start": {
                                "slow_start_time_seconds": 10,
                                "min_weight_percent": 1
                            }
                        }
                    ]
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start is only supported by the roundrobin upstream type/



=== TEST 17: the data plane keeps an upstream it cannot ramp
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local apisix_upstream = require("apisix.upstream")

            -- the Admin API rejects this, but a control plane or an embedded
            -- upstream reaches the data plane without passing through it; the
            -- upstream still has to load, or every route using it returns 503
            local conf = {
                type = "chash",
                key = "remote_addr",
                nodes = {{host = "127.0.0.1", port = 1980, weight = 100, priority = 0}},
                slow_start = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 1,
                },
            }

            local ok, err = apisix_upstream.check_upstream_conf(conf)
            ngx.say("admin: ", tostring(ok), " ", tostring(err))

            local dp_conf = core.table.deepcopy(conf)
            local dp_ok, dp_err = core.schema.check(core.schema.upstream, dp_conf)
            ngx.say("data plane schema: ", tostring(dp_ok), " ", tostring(dp_err))
        }
    }
--- response_body
admin: false slow_start is only supported by the roundrobin upstream type
data plane schema: true nil



=== TEST 18: default_weight needs a kubernetes upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100}
                    ],
                    "slow_start": {
                        "slow_start_time_seconds": 10,
                        "min_weight_percent": 1,
                        "default_weight": 100
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/slow_start.default_weight is only supported by an upstream with discovery_type kubernetes/



=== TEST 19: accept default_weight on a kubernetes upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/4',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "service_name": "default/nginx-service:http",
                    "discovery_type": "kubernetes",
                    "slow_start": {
                        "slow_start_time_seconds": 300,
                        "min_weight_percent": 1,
                        "default_weight": 100
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, uri in ipairs({'/apisix/admin/routes/1',
                                  '/apisix/admin/services/1',
                                  '/apisix/admin/upstreams/1?force=true',
                                  '/apisix/admin/upstreams/4?force=true'}) do
                local code, body = t(uri, ngx.HTTP_DELETE)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(uri, ": ", body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
