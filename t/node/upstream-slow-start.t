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
workers(1);

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

=== TEST 1: the effective weight follows the ramp
--- config
    location /t {
        content_by_lua_block {
            local slow_start = require("apisix.slow_start")
            local conf = {
                slow_start_time_seconds = 300,
                min_weight_percent = 1,
                interval = 1,
                aggression = 1,
            }
            local now = 10000

            -- the first bucket counts as one second of progress, not zero: over a
            -- 10s window that is a tenth of the weight, well above the 1% floor
            ngx.say(slow_start.effective_weight(100, now, {
                slow_start_time_seconds = 10,
                min_weight_percent = 1,
                aggression = 1,
            }, now))
            ngx.say(slow_start.effective_weight(100, now, conf, now))
            ngx.say(slow_start.effective_weight(100, now, conf, now + 30))
            ngx.say(slow_start.effective_weight(100, now, conf, now + 150))
            ngx.say(slow_start.effective_weight(100, now, conf, now + 300))
            ngx.say(slow_start.effective_weight(100, now, conf, now + 3000))
            -- a node configured out of the rotation stays out of it
            ngx.say(slow_start.effective_weight(0, now, conf, now + 30))
            -- anything above zero keeps at least one weight unit
            ngx.say(slow_start.effective_weight(1, now, conf, now + 1))
            -- a node with no state, and a node marked mature, use the full weight
            ngx.say(slow_start.effective_weight(100, nil, conf, now + 1))
            ngx.say(slow_start.effective_weight(100, 0, conf, now + 1))
        }
    }
--- response_body
10
1
10
50
100
100
0
1
100
100



=== TEST 2: min_weight_percent is the floor, aggression the shape
--- config
    location /t {
        content_by_lua_block {
            local slow_start = require("apisix.slow_start")
            local now = 10000
            local function weight(percent, aggression, elapsed)
                return slow_start.effective_weight(100, now, {
                    slow_start_time_seconds = 300,
                    min_weight_percent = percent,
                    aggression = aggression,
                }, now + elapsed)
            end

            ngx.say(weight(20, 1, 1))
            ngx.say(weight(1, 1, 30))
            ngx.say(weight(1, 2, 30) > weight(1, 1, 30))
            ngx.say(weight(1, 0.5, 30) < weight(1, 1, 30))
        }
    }
--- response_body
20
10
true
true



=== TEST 3: a local clock jump does not produce a weight outside the range
--- config
    location /t {
        content_by_lua_block {
            local slow_start = require("apisix.slow_start")
            local conf = {
                slow_start_time_seconds = 300,
                min_weight_percent = 1,
                aggression = 1,
            }

            -- backwards
            ngx.say(slow_start.effective_weight(100, 10000, conf, 9000))
            -- and forwards, clamped to the full window
            ngx.say(slow_start.effective_weight(100, 10000, conf, 99999))
        }
    }
--- response_body
1
100



=== TEST 4: a node added to a running upstream ramps up, the existing one does not
--- timeout: 30
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port"

            local function set_upstream(nodes, desc)
                return t('/apisix/admin/upstreams/1',
                    ngx.HTTP_PUT,
                    [[{
                        "type": "roundrobin",
                        "desc": "]] .. desc .. [[",
                        "nodes": ]] .. nodes .. [[,
                        "warm_up_conf": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": 1,
                            "interval": 1
                        }
                    }]]
                )
            end

            local function split(times)
                local ports = {}
                for _ = 1, times do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    if not res then
                        return nil, err
                    end
                    ports[res.body] = (ports[res.body] or 0) + 1
                end
                return ports
            end

            local one = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100}]]=]
            local two = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100},
                             {"host": "127.0.0.1", "port": 1981, "weight": 100}]]=]

            local code, body = set_upstream(one, "one node")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream_id": "1"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- the first picker build records the bootstrapped node as the baseline
            ngx.sleep(0.5)
            split(1)

            code, body = set_upstream(two, "two nodes")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local ports, err = split(20)
            if not ports then
                ngx.say(err)
                return
            end
            local mature, warming = ports["1980"] or 0, ports["1981"] or 0
            ngx.log(ngx.WARN, "ramping split: 1980=", mature, " 1981=", warming)
            if not (mature >= 17 and warming <= 3) then
                ngx.say("failed while ramping: 1980=", mature, " 1981=", warming)
                return
            end

            -- once the window has passed both nodes are back to their weights
            ngx.sleep(11)
            ports, err = split(20)
            if not ports then
                ngx.say(err)
                return
            end
            if ports["1980"] ~= 10 or ports["1981"] ~= 10 then
                ngx.say("failed after the window: 1980=", tostring(ports["1980"]),
                        " 1981=", tostring(ports["1981"]))
                return
            end

            -- an unrelated field changing must not start the ramp over
            code, body = set_upstream(two, "a new description")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            ports, err = split(20)
            if not ports then
                ngx.say(err)
                return
            end
            if ports["1980"] ~= 10 or ports["1981"] ~= 10 then
                ngx.say("failed after an unrelated change: 1980=",
                        tostring(ports["1980"]), " 1981=", tostring(ports["1981"]))
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed
--- error_log
slow start began for node 127.0.0.1:1981
slow start finished for node 127.0.0.1:1981
--- no_error_log eval
[qr/\[error\]/, qr/\[alert\]/, qr/slow start began for node 127\.0\.0\.1:1980/]



=== TEST 5: a node that comes back inside the tombstone window keeps its progress
--- timeout: 30
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/slow-start-tombstone"

            local function set_upstream(nodes)
                return t('/apisix/admin/upstreams/2',
                    ngx.HTTP_PUT,
                    [[{
                        "type": "roundrobin",
                        "nodes": ]] .. nodes .. [[,
                        "warm_up_conf": {
                            "slow_start_time_seconds": 10,
                            "min_weight_percent": 1,
                            "interval": 10
                        }
                    }]]
                )
            end

            local function split(times)
                local ports = {}
                for _ = 1, times do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    if not res then
                        return nil, err
                    end
                    ports[res.body] = (ports[res.body] or 0) + 1
                end
                return ports
            end

            local one = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100}]]=]
            local two = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100},
                             {"host": "127.0.0.1", "port": 1981, "weight": 100}]]=]

            local code, body = set_upstream(one)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/slow-start-tombstone",
                    "plugins": {
                        "proxy-rewrite": {"uri": "/server_port"}
                    },
                    "upstream_id": "2"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)
            split(1)

            -- 1981 joins and starts its ramp
            set_upstream(two)
            ngx.sleep(0.5)
            split(1)

            -- it leaves, and comes back well inside the 10s tombstone window
            set_upstream(one)
            ngx.sleep(0.5)
            split(1)
            ngx.sleep(4)
            set_upstream(two)
            ngx.sleep(0.5)

            local ports, err = split(100)
            if not ports then
                ngx.say(err)
                return
            end

            -- the ramp continued while it was away, so 1981 is about half way
            -- through the window: a real share of the traffic, still below 1980.
            -- Restarting the ramp would have put it back at a tenth of the weight
            local mature, warming = ports["1980"] or 0, ports["1981"] or 0
            ngx.log(ngx.WARN, "tombstone split: 1980=", mature, " 1981=", warming)
            if warming >= 15 and warming < mature then
                ngx.say("passed")
            else
                ngx.say("failed: 1980=", mature, " 1981=", warming)
            end
        }
    }
--- response_body
passed
--- grep_error_log eval
qr/slow start began for node \S+/
--- grep_error_log_out
slow start began for node 127.0.0.1:1981



=== TEST 6: without warm_up_conf the weights are used as configured
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/3',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100},
                        {"host": "127.0.0.1", "port": 1981, "weight": 100}
                    ]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/slow-start-off",
                    "plugins": {
                        "proxy-rewrite": {"uri": "/server_port"}
                    },
                    "upstream_id": "3"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/slow-start-off"
            local ports = {}
            for _ = 1, 20 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ports[res.body] = (ports[res.body] or 0) + 1
            end

            if ports["1980"] == 10 and ports["1981"] == 10 then
                ngx.say("passed")
            else
                ngx.say("failed: 1980=", tostring(ports["1980"]),
                        " 1981=", tostring(ports["1981"]))
            end
        }
    }
--- response_body
passed
--- no_error_log
slow start began for node



=== TEST 7: a route embedded upstream is its own lifecycle scope
--- timeout: 15
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/slow-start-embedded"

            local function set_route(nodes)
                return t('/apisix/admin/routes/4',
                    ngx.HTTP_PUT,
                    [[{
                        "uri": "/slow-start-embedded",
                        "plugins": {
                            "proxy-rewrite": {"uri": "/server_port"}
                        },
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": ]] .. nodes .. [[,
                            "warm_up_conf": {
                                "slow_start_time_seconds": 10,
                                "min_weight_percent": 1,
                                "interval": 1
                            }
                        }
                    }]]
                )
            end

            local one = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100}]]=]
            local two = [=[[{"host": "127.0.0.1", "port": 1980, "weight": 100},
                             {"host": "127.0.0.1", "port": 1981, "weight": 100}]]=]

            local code, body = set_route(one)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)
            local httpc = http.new()
            httpc:request_uri(uri)

            code, body = set_route(two)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local ports = {}
            for _ = 1, 20 do
                httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ports[res.body] = (ports[res.body] or 0) + 1
            end

            local mature, warming = ports["1980"] or 0, ports["1981"] or 0
            if mature >= 17 and warming <= 3 then
                ngx.say("passed")
            else
                ngx.say("failed: 1980=", mature, " 1981=", warming)
            end
        }
    }
--- response_body
passed
--- error_log eval
qr{of upstream \S*/routes/4}



=== TEST 8: the picker cache key changes once per interval, then settles
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local slow_start = require("apisix.slow_start")
            local dict = ngx.shared["upstream-slow-start"]
            local up_conf = {
                resource_key = "/upstreams/version-suffix",
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 1,
                    interval = 2,
                },
            }

            -- no deadline published yet: the build this triggers is the one that
            -- publishes it, so the key already carries a bucket
            local first = slow_start.version_suffix(up_conf)
            ngx.say("bucketed: ", first ~= nil and first:match("^#w%d+$") ~= nil)

            -- a second request inside the same bucket reuses the cached picker
            ngx.say("stable within the interval: ",
                    slow_start.version_suffix(up_conf) == first)

            local function publish_deadline(deadline)
                local ok, err = dict:set(up_conf.resource_key .. "|!", deadline)
                if not ok then
                    error("failed to publish the deadline: " .. err)
                end
            end

            -- while a node ramps, crossing the bucket rebuilds it exactly once
            publish_deadline(ngx.now() + 10)
            ngx.sleep(2.1)
            local next_bucket = slow_start.version_suffix(up_conf)
            ngx.say("rebuilt after the interval: ", next_bucket ~= first)
            ngx.say("stable again: ", slow_start.version_suffix(up_conf) == next_bucket)

            -- once every node is mature the key stops moving altogether
            publish_deadline(0)
            ngx.say("settled: ", slow_start.version_suffix(up_conf))
            ngx.sleep(2.1)
            ngx.say("still settled: ", slow_start.version_suffix(up_conf))

            dict:delete(up_conf.resource_key .. "|!")
        }
    }
--- timeout: 15
--- response_body
bucketed: true
stable within the interval: true
rebuilt after the interval: true
stable again: true
settled: #wm
still settled: #wm



=== TEST 9: an unhealthy node keeps its lifecycle, it is not treated as removed
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            -- 1979 has nothing listening, so the active check takes it out of the
            -- picker while the configuration still holds it
            local code, body = t('/apisix/admin/upstreams/5',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": [
                        {"host": "127.0.0.1", "port": 1980, "weight": 100},
                        {"host": "127.0.0.1", "port": 1979, "weight": 100}
                    ],
                    "checks": {
                        "active": {
                            "http_path": "/status",
                            "healthy": {"interval": 1, "successes": 1},
                            "unhealthy": {"interval": 1, "tcp_failures": 1}
                        }
                    },
                    "warm_up_conf": {
                        "slow_start_time_seconds": 10,
                        "min_weight_percent": 1,
                        "interval": 1
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/5',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/slow-start-unhealthy",
                    "plugins": {
                        "proxy-rewrite": {"uri": "/server_port"}
                    },
                    "upstream_id": "5"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/slow-start-unhealthy"
            local function hit(times)
                local ports = {}
                for _ = 1, times do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    if not res then
                        return nil, err
                    end
                    ports[res.body] = (ports[res.body] or 0) + 1
                end
                return ports
            end

            -- requests before the checker has taken 1979 out may land on it and
            -- come back as a 502; only a request that cannot be made at all fails
            local ports, err
            ngx.sleep(0.5)
            ports, err = hit(2)
            if not ports then
                ngx.say("request failed: ", err)
                return
            end
            -- let the active checker settle and keep rebuilding the picker
            ngx.sleep(3)
            ports, err = hit(5)
            if not ports then
                ngx.say("request failed: ", err)
                return
            end
            ngx.sleep(2)
            ports, err = hit(10)
            if not ports then
                ngx.say("request failed: ", err)
                return
            end

            ngx.say("1980: ", ports["1980"] or 0)
        }
    }
--- response_body
1980: 10
--- no_error_log
left the upstream



=== TEST 10: a node kept out of the picker starts its window when it first gets in
--- config
    location /t {
        content_by_lua_block {
            local slow_start = require("apisix.slow_start")
            local n1 = {host = "10.0.0.1", port = 8080, weight = 100, priority = 0}
            local n2 = {host = "10.0.0.2", port = 8080, weight = 100, priority = 0}
            local up_conf = {
                resource_key = "/upstreams/pending",
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 100,
                    min_weight_percent = 1,
                    interval = 1,
                    aggression = 1,
                },
            }

            -- the upstream is bootstrapped with one node
            up_conf.nodes = {n1}
            local weights = slow_start.effective_weights(up_conf, {n1})
            ngx.say("baseline: ", weights[1])

            -- a second node is configured, but a health check keeps it out of the
            -- picker for a while. It must not age into maturity while sidelined
            up_conf.nodes = {n1, n2}
            weights = slow_start.effective_weights(up_conf, {n1})
            ngx.say("while sidelined: ", weights[1], " ", tostring(weights[2]))

            -- the first picker it reaches is where its window starts
            weights = slow_start.effective_weights(up_conf, {n1, n2})
            ngx.say("first picker: ", weights[1], " ", weights[2])
        }
    }
--- response_body
baseline: 100
while sidelined: 100 nil
first picker: 100 1
--- error_log
slow start began for node 10.0.0.2:8080



=== TEST 11: a worker never writes back a ramp start another worker just changed
--- config
    location /t {
        content_by_lua_block {
            local slow_start = require("apisix.slow_start")
            local dict = ngx.shared["upstream-slow-start"]
            local mt = getmetatable(dict)
            local orig_get = mt.get

            -- Reconciles in different workers run truly in parallel. Replay the
            -- losing interleaving deterministically: this worker reads a node's
            -- state, and another worker writes before this one does
            local function race(target, other_worker)
                local fired = false
                mt.get = function(self, key, ...)
                    local value, flags = orig_get(self, key, ...)
                    if self == dict and key == target and not fired then
                        fired = true
                        other_worker()
                    end
                    return value, flags
                end
            end

            local function run(fn)
                local ok, err = pcall(fn)
                mt.get = orig_get
                if not ok then
                    error(err)
                end
            end

            local conf = {
                slow_start_time_seconds = 100,
                min_weight_percent = 1,
                interval = 1,
                aggression = 1,
            }
            local n1 = {host = "10.0.1.1", port = 80, weight = 100, priority = 0}
            local n2 = {host = "10.0.1.2", port = 80, weight = 100, priority = 0}
            local scope = "/upstreams/race"
            local key = scope .. "|10.0.1.2:80"
            local up_conf = {resource_key = scope, type = "roundrobin", warm_up_conf = conf}

            up_conf.nodes = {n1}
            slow_start.effective_weights(up_conf, {n1})
            up_conf.nodes = {n1, n2}
            slow_start.effective_weights(up_conf, {n1})
            ngx.say("pending: ", dict:get(key))

            -- both workers see n2 enter the picker; the other one elects first
            local elected = ngx.now() - 50
            local weights
            run(function()
                race(key, function()
                    assert(dict:add(key .. "@-1", elected, 10))
                    assert(dict:set(key, elected))
                end)
                weights = slow_start.effective_weights(up_conf, {n1, n2})
            end)
            ngx.say("adopted the elected start: ", dict:get(key) == elected,
                    ", weight ", weights[2])

            -- the other worker finishes the ramp while this one, having read the
            -- old start, only means to refresh it
            run(function()
                race(key, function()
                    assert(dict:add(key .. "@" .. elected, 0, 10))
                    assert(dict:set(key, 0))
                end)
                slow_start.effective_weights(up_conf, {n1, n2})
            end)
            ngx.say("refresh left the change alone: ", dict:get(key))
        }
    }
--- response_body
pending: -1
adopted the elected start: true, weight 50
refresh left the change alone: 0



=== TEST 12: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, uri in ipairs({'/apisix/admin/routes/1', '/apisix/admin/routes/2',
                                  '/apisix/admin/routes/3', '/apisix/admin/routes/4',
                                  '/apisix/admin/routes/5',
                                  '/apisix/admin/upstreams/1?force=true', '/apisix/admin/upstreams/2?force=true',
                                  '/apisix/admin/upstreams/3?force=true', '/apisix/admin/upstreams/5?force=true'}) do
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
