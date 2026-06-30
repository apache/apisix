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
log_level('warn');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: stale targets are purged for every checker, not just the first one
# Two upstreams each have active health checks enabled. When their `checks`
# config changes, the health-check manager rebuilds each checker and marks the
# old targets via delayed_clear(); the health-check library must then purge the
# dropped node from the shm target list of *every* checker. A library bug
# cleaned only the first checker per window, so with multiple health-checked
# upstreams the others kept their deleted nodes forever -- still reported by the
# control API (apache/apisix#13385) and still actively probed (apache/apisix#13141).
# Reproduces only with multiple upstreams; a single-upstream setup always cleans
# (it is the "first" checker). The reconfigure changes `checks` (not just nodes)
# so it always goes through the delayed_clear rebuild path, independent of any
# incremental-update optimization.
--- config
location /t {
    content_by_lua_block {
        local json = require("toolkit.json")
        local t = require("lib.test_admin").test

        local function put_route(id, uri, nodes, interval)
            local cfg = {
                uri = uri,
                upstream = {
                    type = "roundrobin",
                    nodes = nodes,
                    checks = {
                        active = {
                            type = "tcp",
                            healthy   = { interval = interval, successes = 1 },
                            unhealthy = { interval = interval, tcp_failures = 1 },
                        },
                    },
                },
            }
            assert(t('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, cfg) < 300)
        end

        -- two upstreams, each health-checked, each with two nodes
        put_route(1, "/hello1", { ["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1 }, 1)
        put_route(2, "/hello2", { ["127.0.0.1:1980"] = 1, ["127.0.0.1:1982"] = 1 }, 1)

        -- traffic instantiates both checkers and registers them with the
        -- shared active-check timer
        t('/hello1', ngx.HTTP_GET)
        t('/hello2', ngx.HTTP_GET)
        ngx.sleep(2)

        -- count the soon-to-be-removed nodes (1981, 1982) present across all
        -- checkers. A node in a checker's target list IS being actively probed,
        -- so this is the count of nodes under active health check.
        local function count_targets(ports)
            local _, _, res = t('/v1/healthcheck', ngx.HTTP_GET)
            local n = 0
            for _, info in ipairs(json.decode(res)) do
                for _, node in ipairs(info.nodes or {}) do
                    if ports[node.port] then
                        n = n + 1
                    end
                end
            end
            return n
        end

        local removed = { [1981] = true, [1982] = true }
        -- both nodes are registered and actively probed before removal
        ngx.say("probed_before: ", count_targets(removed))

        -- drop one node and change the checks config (interval 1 -> 2) on each
        -- upstream: the manager rebuilds the checker and delayed_clear()s the
        -- old targets, so the dropped node must be purged by the library
        put_route(1, "/hello1", { ["127.0.0.1:1980"] = 1 }, 2)
        put_route(2, "/hello2", { ["127.0.0.1:1980"] = 1 }, 2)
        t('/hello1', ngx.HTTP_GET)
        t('/hello2', ngx.HTTP_GET)

        -- wait past DELAYED_CLEAR_TIMEOUT (10s) plus a cleanup window
        ngx.sleep(15)

        -- after the purge the removed nodes are gone from every checker, so they
        -- can neither be queried via the control API (#13385) nor probed (#13141)
        ngx.say("stale_after: ", count_targets(removed))
    }
}
--- request
GET /t
--- response_body
probed_before: 2
stale_after: 0
--- ignore_error_log
--- timeout: 30
