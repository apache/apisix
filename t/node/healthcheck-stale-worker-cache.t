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
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: fetch_node_status reads shm, not the worker-local event cache
# resty.healthcheck.get_target_status reads a per-worker cache filled by
# resty.events. Active checks run on one worker and write shm first; a peer
# that missed the event (or whose checker was created after the flip) keeps
# a stale "healthy" cache. Routing must consult shm (apache/apisix#13888).
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local hm = require("apisix.healthcheck_manager")

            local checks = {
                active = {
                    type = "http",
                    http_path = "/status",
                    healthy = { interval = 100, successes = 1 },
                    unhealthy = { interval = 100, http_failures = 2 },
                },
            }

            local checker, err = healthcheck.new({
                name = "upstream#test-stale-worker-cache",
                shm_name = "upstream-healthcheck",
                events_module = "resty.events",
                checks = checks,
            })
            if not checker then
                ngx.say("new failed: ", err)
                return
            end

            local ok
            ok, err = checker:add_target("127.0.0.1", 1980, nil, true)
            if not ok then
                ngx.say("add_target failed: ", err)
                checker:stop()
                return
            end

            -- add_target publishes the initial state asynchronously. Wait until
            -- this worker has the healthy local view before flipping SHM alone.
            local local_healthy
            for _ = 1, 40 do
                local_healthy = checker:get_target_status("127.0.0.1", 1980,
                                                          "127.0.0.1")
                if local_healthy then
                    break
                end
                ngx.sleep(0.05)
            end
            assert(local_healthy, "local cache should become healthy")

            -- another worker marked the node unhealthy in shm without an event
            local key = checker.TARGET_STATE .. ":127.0.0.1:1980:127.0.0.1"
            assert(checker.shm:set(key, 2)) -- 2 = unhealthy

            local healthy = hm.fetch_node_status(checker, "127.0.0.1", 1980, "127.0.0.1")
            checker:stop()
            ngx.say(healthy and "healthy" or "unhealthy")
        }
    }
--- request
GET /t
--- response_body
unhealthy
--- timeout: 10



=== TEST 2: priority failover stops sending traffic once shm marks the primary unhealthy
# Same gap as TEST 1, through the balancer: after the picker is cached on
# status_ver (which only bumps on a local event), a shm-only flip must still
# rebuild the picker and fail over to the backup node.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local healthcheck = require("resty.healthcheck")

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": [
                            {"host": "127.0.0.1", "port": 1980, "weight": 1, "priority": 0},
                            {"host": "127.0.0.1", "port": 1981, "weight": 1, "priority": -1}
                        ],
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "healthy": {
                                    "interval": 100,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 100,
                                    "http_failures": 2
                                }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say(body)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port"
            local function hit()
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    return nil, err
                end
                return res.body
            end

            -- enqueue checker creation and wait for the timer to publish it
            local port, err = hit()
            if not port then
                ngx.say("warmup failed: ", err)
                return
            end
            ngx.sleep(2)

            -- picker is now cached against this worker's still-healthy local view
            port, err = hit()
            if port ~= "1980" then
                ngx.say("expected primary 1980 before shm flip, got ", port or err)
                return
            end

            local name = "upstream#/apisix/routes/1"
            local list = healthcheck.get_target_list(name, "upstream-healthcheck")
            if not list then
                ngx.say("no shm target list")
                return
            end

            local shm = ngx.shared["upstream-healthcheck"]
            local flipped = false
            for _, target in ipairs(list) do
                if tonumber(target.port) == 1980 then
                    local key = "lua-resty-healthcheck:" .. name .. ":state:"
                                .. target.ip .. ":" .. target.port .. ":" .. target.hostname
                    assert(shm:set(key, 2)) -- unhealthy, no event
                    flipped = true
                end
            end
            if not flipped then
                ngx.say("primary not in shm target list")
                return
            end

            local ports = {}
            for i = 1, 8 do
                port, err = hit()
                if not port then
                    ngx.say("request ", i, " failed: ", err)
                    return
                end
                ports[#ports + 1] = port
            end

            for i, p in ipairs(ports) do
                if p ~= "1981" then
                    ngx.say("request ", i, " still hit ", p, " after shm unhealthy")
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
--- timeout: 10


=== TEST 3: a worker without a checker reads the shared target state
# Another worker has marked the primary unhealthy before this worker creates
# its checker. Exercise the nil-checker lookup directly to avoid a race with
# the asynchronous checker-creation timer.
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local hm = require("apisix.healthcheck_manager")
            local checks = {
                active = {
                    http_path = "/status",
                    healthy = { interval = 100, successes = 1 },
                    unhealthy = { interval = 100, http_failures = 2 },
                },
            }
            local path = "/apisix/routes/2"
            local name = "upstream#" .. path
            local shadow = assert(healthcheck.new({
                name = name,
                shm_name = "upstream-healthcheck",
                events_module = "resty.events",
                checks = checks,
            }))
            assert(shadow:add_target("127.0.0.1", 1980, nil, true))
            assert(shadow:add_target("127.0.0.1", 1981, nil, true))
            local key = shadow.TARGET_STATE .. ":127.0.0.1:1980:127.0.0.1"
            assert(shadow.shm:set(key, 2))
            shadow:stop()

            assert(shadow.shm:get(key) == 2)
            assert(hm.fetch_node_status(nil, "127.0.0.1", 1980,
                                        "127.0.0.1", path) == false)
            assert(hm.fetch_node_status(nil, "127.0.0.1", 1981,
                                        "127.0.0.1", path) == true)
            local nodes = {
                { host = "127.0.0.1", port = 1980 },
                { host = "127.0.0.1", port = 1981 },
            }
            assert(hm.node_status_ver(nil, nodes, nil, nil, path) == "x:0:1")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- timeout: 10
