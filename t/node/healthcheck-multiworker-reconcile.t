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
workers(2);
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: shared shm target list converges to the desired set under config churn (2 workers)
# With real requests round-robining across two workers, each worker reconciles the
# checker through its own request path/timers. The target membership lives in a
# shm shared by checker name, so its final state must equal the desired node set
# after every kind of change -- node add/remove (incremental) and a checks-config
# change (rebuild) -- with no orphan targets and no purge of surviving targets
# (apache/apisix#13282, multi-worker).
#
# NOTE: this is a convergence/non-regression check, not a deterministic
# reproduction of the cross-worker asymmetry -- requests are distributed across
# workers by the OS accept(), so it cannot force the "one worker rebuilds while
# another destroys" interleaving. The authoritative deterministic reproduction
# is TEST 6 in healthcheck-incremental-update.t.
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local http = require("resty.http")
        local t = require("lib.test_admin").test

        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        local function cfg(nodes, interval)
            return [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": ]] .. nodes .. [[,
                    "checks": { "active": { "type": "tcp",
                        "healthy": { "interval": ]] .. interval .. [[, "successes": 1 },
                        "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
                }
            }]]
        end

        -- drive real traffic so requests spread across both workers; assert the
        -- requests actually succeed, otherwise a silent upstream failure could
        -- leave the shm unchanged and let the assertions pass without exercising
        -- checker creation/reconciliation
        local function drive()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _ = 1, 16 do
                local httpc = http.new()
                local res = httpc:request_uri(uri, { method = "GET", keepalive = false })
                assert(res and res.status == 200, "drive request failed")
            end
        end

        -- the desired set is worker-agnostic: read it from the shared shm
        local function shm_ports()
            local list = healthcheck.get_target_list(NAME, SHM) or {}
            local ports = {}
            for _, tg in ipairs(list) do
                ports[#ports + 1] = tg.port
            end
            table.sort(ports)
            return table.concat(ports, ",")
        end

        ngx.sleep(2) -- let both workers settle

        -- phase 1: two nodes -> both must be registered
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1981": 1}', 1)) < 300)
        drive()
        ngx.sleep(3)
        ngx.say("phase1: ", shm_ports())

        -- phase 2: node-only change (remove 1981, add 1982) -> incremental reconcile,
        -- shm must drop the orphan and add the new node
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1982": 1}', 1)) < 300)
        drive()
        ngx.sleep(3)
        ngx.say("phase2: ", shm_ports())

        -- phase 3: checks-config change (interval 1 -> 2), same nodes -> rebuild.
        -- wait past DELAYED_CLEAR_TIMEOUT (10s): surviving targets must NOT be purged
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1982": 1}', 2)) < 300)
        drive()
        ngx.sleep(14)
        ngx.say("phase3: ", shm_ports())
    }
}
--- request
GET /t
--- response_body
phase1: 1980,1981
phase2: 1980,1982
phase3: 1980,1982
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 40



=== TEST 2: an unhealthy node is detected and filtered consistently across workers
# The basic multi-worker health scenario: a healthy node (1980) and a dead node
# (1970). Active checks must mark 1970 unhealthy in the shared shm, and with
# retries=0 every request across both workers must still succeed -- proving both
# workers filter the unhealthy node (a per-worker miss would send some requests
# to 1970 and fail). This verifies health STATUS propagation, not just membership.
--- config
location /t {
    content_by_lua_block {
        local http = require("resty.http")
        local t = require("lib.test_admin").test
        local json = require("apisix.core.json")

        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
            "uri": "/server_port",
            "upstream": {
                "type": "roundrobin",
                "retries": 0,
                "nodes": {"127.0.0.1:1980": 1, "127.0.0.1:1970": 1},
                "checks": { "active": { "type": "tcp",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
            }
        }]]) < 300)

        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port"
        -- a burst returns how many of n requests did NOT get 200 from 1980, i.e.
        -- landed on the dead node 1970 (retries=0 -> hard failure) or errored
        local function burst(n)
            local errors = 0
            for _ = 1, n do
                local httpc = http.new()
                local r = httpc:request_uri(uri, { method = "GET", keepalive = false })
                if not r or r.status ~= 200 or r.body ~= "1980" then
                    errors = errors + 1
                end
            end
            return errors
        end

        -- Drive traffic until every worker has built its checker AND converged its
        -- per-worker status cache to "1970 unhealthy". The shared shm reports 1970
        -- unhealthy as soon as ANY one worker probes, so the control-API status is
        -- necessary but NOT sufficient -- only routing proves BOTH workers filter.
        -- Require several consecutive zero-error bursts (bounded); a genuine
        -- per-worker filtering miss keeps producing errors and never converges,
        -- so the test fails instead of flaking on a fixed sleep.
        local clean_streak = 0
        for _ = 1, 25 do
            if burst(12) == 0 then
                clean_streak = clean_streak + 1
                if clean_streak >= 3 then
                    break
                end
            else
                clean_streak = 0
            end
            ngx.sleep(1)
        end
        ngx.say("converged: ", tostring(clean_streak >= 3))

        -- health status from the shared shm (worker-agnostic) via the control API
        local function healthy(status)
            return status == "healthy" or status == "mostly_healthy"
        end
        local _, _, res = t('/v1/healthcheck', ngx.HTTP_GET)
        local h1970, h1980
        for _, info in ipairs(json.decode(res)) do
            for _, node in ipairs(info.nodes or {}) do
                if node.port == 1970 then h1970 = healthy(node.status) end
                if node.port == 1980 then h1980 = healthy(node.status) end
            end
        end
        ngx.say("1970_healthy: ", tostring(h1970))
        ngx.say("1980_healthy: ", tostring(h1980))
    }
}
--- request
GET /t
--- response_body
converged: true
1970_healthy: false
1980_healthy: true
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 40
