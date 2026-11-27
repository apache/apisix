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

=== TEST 1: an initial add failure is retried without changing the upstream configuration
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port"
        state.armed = "add"
        state.put(1, true)
        state.seed()

        -- No further route traffic or config update drives the retry. The
        -- working-pool timer must notice that registration was incomplete.
        state.wait_for(function()
            return state.add_calls >= 2 and state.unhealthy()
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)
        ngx.say("registered targets: ", #state.targets())
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node add attempts: 2
checkers created: 1
healthy-node add attempts: 1
healthy-node remove attempts: 0
registered targets: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 30



=== TEST 2: retrying a rebuild unmarks a target whose re-add failed
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_route2"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "add"
        state.put(2, true)
        assert(state.wait_for(function() return state.failures == 1 end), "no failure injected")
        assert(state.failed_purge_time, "rebuild did not mark the old target for cleanup")
        state.wait_for(function()
            local targets = state.targets()
            for _, target in ipairs(targets) do
                if target.port == 1970 then
                    return state.add_calls >= 3 and target.purge_time == nil
                end
            end
            return false
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)

        -- The real cleanup timer must not remove this desired target after
        -- the old delayed-clear deadline (10 seconds) and a cleanup interval.
        local remaining = state.failed_purge_time + 3 - ngx.now()
        if remaining > 0 then
            ngx.sleep(remaining)
        end
        ngx.say("registered targets after cleanup: ", #state.targets())
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node add attempts: 3
checkers created: 2
healthy-node add attempts: 2
healthy-node remove attempts: 0
registered targets after cleanup: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 55



=== TEST 3: a failed stale-target removal during rebuild is retried
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_hello"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "remove"
        state.put(2, false)
        state.wait_for(function()
            return state.remove_calls >= 2 and #state.targets() == 1
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node remove attempts: ", state.remove_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)
        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        ngx.say("registered ports: ", table.concat(ports, ","))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node remove attempts: 2
checkers created: 2
healthy-node add attempts: 2
healthy-node remove attempts: 0
registered ports: 1980
healthy responses: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 40



=== TEST 4: a deleted target list does not reset an unhealthy target to healthy
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "add"
        state.delete_on_failure = true
        state.put(60, true)
        assert(state.wait_for(function()
            return state.created >= 2 and state.add_calls >= 3 and #state.targets() == 2
        end), "target reconstruction did not finish")
        assert(state.wait_for(state.unhealthy),
               "reconstructed target did not remain unhealthy")

        local state_key = state.current.TARGET_STATE .. ":127.0.0.1:1970:127.0.0.1"
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("shared dead-node state: ",
                ngx.shared["upstream-healthcheck"]:get(state_key))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 5: a deleted target list does not leave a local ghost
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_hello"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "remove"
        state.delete_on_failure = true
        state.put(60, false)
        assert(state.wait_for(function()
            return state.created >= 2 and state.remove_calls >= 2 and #state.targets() == 1
        end), "stale-target removal did not finish")
        assert(state.wait_for(state.removed), "the worker kept a removed target")

        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        local removed_status, removed_err = state.current:get_target_status("127.0.0.1", 1970)
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("dead-node remove attempts: ", state.remove_calls)
        ngx.say("registered ports: ", table.concat(ports, ","))
        ngx.say("removed target status: ", tostring(removed_status), "/", tostring(removed_err))
        state.traffic()

        state.put(60, true)
        assert(state.wait_for(function()
            return state.add_calls >= 2
                   and state.current:get_target_status("127.0.0.1", 1970) == true
        end), "the re-added target did not use the default health state")
        ngx.say("re-added target healthy: ",
                tostring(state.current:get_target_status("127.0.0.1", 1970)))
        state.traffic("healthy responses after re-add: ")

        state.put(1, true)
        assert(state.wait_for(state.unhealthy), "the re-added dead node was not probed")
        state.traffic("healthy responses after final probe: ")
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
dead-node remove attempts: 2
registered ports: 1980
removed target status: nil/target not found
healthy responses: 40
re-added target healthy: true
healthy responses after re-add: 20
healthy responses after final probe: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 90



=== TEST 6: reconstruction during create_checker preserves an unhealthy survivor
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port"
        state.put(1, true, 1960)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "remove"
        state.armed_port = 1960
        state.delete_on_failure = true
        state.put(60, true, false)
        assert(state.wait_for(function()
            local stale_status = state.current:get_target_status("127.0.0.1", 1960)
            return state.created >= 2 and state.add_calls >= 2
                   and state.stale_remove_calls >= 2 and #state.targets() == 2
                   and stale_status == nil
        end), "create_checker reconstruction did not finish")
        assert(state.wait_for(state.unhealthy),
               "create_checker reset the surviving target's health")

        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        local state_key = state.current.TARGET_STATE .. ":127.0.0.1:1970:127.0.0.1"
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("stale-node remove attempts: ", state.stale_remove_calls)
        ngx.say("registered ports: ", table.concat(ports, ","))
        ngx.say("shared dead-node state: ",
                ngx.shared["upstream-healthcheck"]:get(state_key))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
dead-node add attempts: 2
stale-node remove attempts: 2
registered ports: 1970,1980
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 7: retry a nodes-only addition with the same checker after losing the target list
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_aa"
        local checker = state.prepare_nodes_update()

        state.armed = "add"
        state.armed_port = 1981
        state.put(60, true, 1981)
        -- No route traffic or further configuration change drives the retry.
        assert(state.wait_for(function()
            return state.failures == 1 and #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1981) == true
        end), "the working-pool timer did not finish the addition")

        ngx.say("same checker: ", checker == state.current)
        ngx.say("shared dead-node state: ", state.shared_status(1970))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic("healthy responses: ", "1981")
    }
}
--- request
GET /t
--- response_body
same checker: true
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1981
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 8: retry a nodes-only removal and allow a later addition to start healthy
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_route2"
        local checker = state.prepare_nodes_update(1960)

        state.armed = "remove"
        state.armed_port = 1960
        state.put(60, true)
        assert(state.wait_for(function()
            local status, err = state.current:get_target_status("127.0.0.1", 1960)
            return state.failures == 1 and #state.targets() == 2
                   and status == nil and err == "target not found"
                   and state.shared_status(1960) == nil
        end), "the working-pool timer did not finish the removal")

        ngx.say("same checker: ", checker == state.current)
        ngx.say("shared dead-node state: ", state.shared_status(1970))
        ngx.say("surviving dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()

        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1960) == true
        end), "the re-added node did not start healthy")
        ngx.say("same checker after re-add: ", checker == state.current)
        ngx.say("shared re-added node state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
same checker: true
shared dead-node state: 2
surviving dead node unhealthy: true
healthy responses: 40
same checker after re-add: true
shared re-added node state: 1
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 9: replacing the probe Host starts a fresh registration on the same address
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- upstream_server_config
location = /host-health {
    content_by_lua_block {
        if ngx.var.server_port == "1981" and ngx.var.host == "old.example" then
            return ngx.exit(503)
        end
        return ngx.exit(200)
    }
}
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        local test = require("lib.test_admin").test
        state.uri = "/server_port_aa"
        local upstream = {
            type = "roundrobin", retries = 0,
            nodes = { ["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1 },
            pass_host = "rewrite", upstream_host = "old.example",
            checks = { active = {
                type = "http", http_path = "/host-health",
                healthy = { interval = 1, successes = 1 },
                -- A failed registration stays out of rotation until after the test.
                unhealthy = { interval = 60, http_failures = 1 },
            } },
        }
        local route = { uri = state.uri, upstream = upstream }
        assert(test("/apisix/admin/routes/1", ngx.HTTP_PUT, route) < 300)
        state.seed()
        assert(state.wait_for(function()
            return state.current and state.current:get_target_status("127.0.0.1", 1981) == false
        end), "the old Host was not marked unhealthy")
        local checker = state.current

        -- Reconciliation removes both old registrations and adds the new ones
        -- in one pass, before the worker necessarily receives its remove events.
        upstream.upstream_host = "new.example"
        assert(test("/apisix/admin/routes/1", ngx.HTTP_PUT, route) < 300)
        assert(state.wait_for(function()
            local targets = state.targets()
            local healthy = state.current:get_target_status("127.0.0.1", 1981)
            return #targets == 2 and targets[1].hostheader == "new.example"
                   and targets[2].hostheader == "new.example"
                   and healthy == (state.shared_status(1981) == 1)
        end), "the new probe Host was not configured")
        ngx.say("same checker: ", state.current == checker)
        ngx.say("new registration shared state: ", state.shared_status(1981))

        local responses = { ["1980"] = 0, ["1981"] = 0 }
        for _ = 1, 40 do
            local code, _, port = test(state.uri, ngx.HTTP_GET)
            assert(code == 200 and responses[port], "unexpected upstream response")
            responses[port] = responses[port] + 1
        end
        ngx.say("responses per upstream: ", responses["1980"], "/", responses["1981"])
    }
}
--- request
GET /t
--- response_body
same checker: true
new registration shared state: 1
responses per upstream: 20/20
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 40
