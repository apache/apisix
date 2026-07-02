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

        -- drive real traffic so requests spread across both workers
        local function drive()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _ = 1, 16 do
                local httpc = http.new()
                httpc:request_uri(uri, { method = "GET", keepalive = false })
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
--- ignore_error_log
--- timeout: 40
